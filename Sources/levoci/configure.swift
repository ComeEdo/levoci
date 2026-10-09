import NIOSSL
import Fluent
import FluentMySQLDriver
import Leaf
import Vapor
import Smtp
import JWT

/// Configurazione principale dell'applicazione Vapor
func configure(_ app: Application) async throws {
    let rawPort = try requireEnv("PORT")
    guard let port = Int(rawPort) else {
        throw ConfigurationError.invalidEnvironmentVariable(name: "PORT", value: rawPort)
    }
    app.http.server.configuration.port = port
    app.http.server.configuration.hostname = Environment.get("HOSTNAME") ?? "127.0.0.1"

    if let rawLogLevel = Environment.get("LOG_LEVEL"),
       let level = Logger.Level(rawValue: rawLogLevel.lowercased()) {
        app.logger.logLevel = level
    }

    let DATABASE_HOST = try requireEnv("DATABASE_HOST")
    let DATABASE_USERNAME = try requireEnv("DATABASE_USERNAME")
    let DATABASE_NAME = try requireEnv("DATABASE_NAME")

    let DATABASE_PORT: Int
    if let rawPort = Environment.get("DATABASE_PORT"), !rawPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        guard let port = Int(rawPort) else {
            throw ConfigurationError.invalidEnvironmentVariable(name: "DATABASE_PORT", value: rawPort)
        }
        DATABASE_PORT = port
    } else {
        DATABASE_PORT = MySQLConfiguration.ianaPortNumber
    }

    let DATABASE_PASSWORD = Environment.get("DATABASE_PASSWORD") ?? ""
    
    let tlsConfiguration: TLSConfiguration? = try makeDatabaseTLSConfiguration(app: app)
    
    let DBConfig: MySQLConfiguration = MySQLConfiguration(
        hostname: DATABASE_HOST,
        port: DATABASE_PORT,
        username: DATABASE_USERNAME,
        password: DATABASE_PASSWORD,
        database: DATABASE_NAME,
        tlsConfiguration: tlsConfiguration
    )
    
    let DATABASE_POOL_LIMIT = Environment.get("DATABASE_POOL_LIMIT").flatMap(Int.init) ?? 5
    
    app.databases.use(DatabaseConfigurationFactory.mysql(configuration: DBConfig, maxConnectionsPerEventLoop: DATABASE_POOL_LIMIT), as: .mysql)

    try await configureJWT(app: app)
    try configureSmtp(app: app)

    app.middleware.use(CustomErrorMiddleware())

    app.migrations.add(CreateCredentials())
    app.migrations.add(CreateAcademicStructure())
    app.migrations.add(CreateUsers())
    app.migrations.add(CreatePostsAndVotes())

    //app.views.use(.leaf) ancora no

    try routes(app)
}

/// Errori di configurazione dell'applicazione e delle variabili d'ambiente
enum ConfigurationError: Error, LocalizedError {
    case missingEnvironmentVariable(name: String)
    case invalidEnvironmentVariable(name: String, value: String)
    case missingKeyFile(name: String, path: String)
    case invalidKeyFile(name: String, reason: String)

    var errorDescription: LocalizedStringResource {
        switch self {
        case .missingEnvironmentVariable(let name):
            return "Variabile d'ambiente mancante o vuota nel file .env: \(name)"
        case .invalidEnvironmentVariable(let name, let value):
            return "Valore non valido per la variabile d'ambiente \(name): '\(value)'"
        case .missingKeyFile(let name, let path):
            return "File di chiave asimmetrica mancante per \(name) al percorso: \(path)"
        case .invalidKeyFile(let name, let reason):
            return "File di chiave asimmetrica non valido per \(name): \(reason)"
        }
    }
}

/// Helper per estrarre variabili d'ambiente obbligatorie
func requireEnv(_ key: String) throws -> String {
    guard let value = Environment.get(key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ConfigurationError.missingEnvironmentVariable(name: key)
    }
    return value
}

/// Risolve percorsi relativi rispetto alla working directory del progetto con fallback a cwd
private func resolvePath(_ rawPath: String, rootDirectory: String) -> String {
    if rawPath.hasPrefix("/") {
        return rawPath
    }
    let normalizedRoot = rootDirectory.hasSuffix("/") ? rootDirectory : rootDirectory + "/"
    let cleanRelative = rawPath.hasPrefix("./") ? String(rawPath.dropFirst(2)) : rawPath
    let combined = normalizedRoot + cleanRelative
    if FileManager.default.fileExists(atPath: combined) {
        return combined
    }
    let cwd = FileManager.default.currentDirectoryPath
    let cwdCombined = (cwd.hasSuffix("/") ? cwd : cwd + "/") + cleanRelative
    if FileManager.default.fileExists(atPath: cwdCombined) {
        return cwdCombined
    }
    return combined
}

/// Configura le chiavi asimmetriche RSA (RS256) per JWT e registra il TokenService.
/// Verifica obbligatoriamente la presenza delle variabili d'ambiente e l'esistenza fisica
/// dei file contenenti la chiave privata e pubblica.
private func configureJWT(app: Application) async throws {
    let rawPrivateKeyPath = try requireEnv("JWT_PRIVATE_KEY_PATH")
    let rawPublicKeyPath = try requireEnv("JWT_PUBLIC_KEY_PATH")

    let rootDir = app.directory.workingDirectory
    let privateKeyPath = resolvePath(rawPrivateKeyPath, rootDirectory: rootDir)
    let publicKeyPath = resolvePath(rawPublicKeyPath, rootDirectory: rootDir)

    guard FileManager.default.fileExists(atPath: privateKeyPath) else {
        throw ConfigurationError.missingKeyFile(name: "JWT_PRIVATE_KEY_PATH", path: privateKeyPath)
    }
    guard FileManager.default.fileExists(atPath: publicKeyPath) else {
        throw ConfigurationError.missingKeyFile(name: "JWT_PUBLIC_KEY_PATH", path: publicKeyPath)
    }

    let privateKeyPEM = try String(contentsOfFile: privateKeyPath, encoding: .utf8)
    let publicKeyPEM = try String(contentsOfFile: publicKeyPath, encoding: .utf8)

    let privateKey: JWTKit.Insecure.RSA.PrivateKey
    do {
        privateKey = try JWTKit.Insecure.RSA.PrivateKey(pem: privateKeyPEM)
    } catch {
        throw ConfigurationError.invalidKeyFile(name: "JWT_PRIVATE_KEY_PATH", reason: error.localizedDescription)
    }

    let publicKey: JWTKit.Insecure.RSA.PublicKey
    do {
        publicKey = try JWTKit.Insecure.RSA.PublicKey(pem: publicKeyPEM)
    } catch {
        throw ConfigurationError.invalidKeyFile(name: "JWT_PUBLIC_KEY_PATH", reason: error.localizedDescription)
    }

    guard privateKey.publicKey == publicKey else {
        throw ConfigurationError.invalidKeyFile(name: "JWT_PUBLIC_KEY_PATH", reason: "La chiave pubblica non corrisponde alla chiave privata fornita.")
    }

    await app.jwt.keys.add(rsa: privateKey, digestAlgorithm: .sha256)

    app.logger.notice("[JWT] Configurazione completata con successo (RS256, Private Key & Public Key caricate)")
}

/// Crea la configurazione Mutual TLS (Two-Way SSL) per il client MariaDB a partire dalle variabili d'ambiente
private func makeDatabaseTLSConfiguration(app: Application) throws -> TLSConfiguration? {
    guard let rawCaPath = Environment.get("DATABASE_CA_CERT_PATH"),
          let rawCertPath = Environment.get("DATABASE_CLIENT_CERT_PATH"),
          let rawKeyPath = Environment.get("DATABASE_CLIENT_KEY_PATH") else {
        return nil
    }

    let rootDir = app.directory.workingDirectory
    let caPath = resolvePath(rawCaPath, rootDirectory: rootDir)
    let certPath = resolvePath(rawCertPath, rootDirectory: rootDir)
    let keyPath = resolvePath(rawKeyPath, rootDirectory: rootDir)
    
    var tlsConfig = TLSConfiguration.makeClientConfiguration()
    tlsConfig.trustRoots = .file(caPath)
    
    let certificates = try NIOSSLCertificate.fromPEMFile(certPath)
    tlsConfig.certificateChain = certificates.map { .certificate($0) }
    
    let privateKey = try NIOSSLPrivateKey(file: keyPath, format: .pem)
    tlsConfig.privateKey = .privateKey(privateKey)

    if Environment.get("DATABASE_TLS_VERIFY")?.lowercased() == "false" {
        tlsConfig.certificateVerification = .none
    } else {
        tlsConfig.certificateVerification = .fullVerification
    }

    return tlsConfig
}

/// Configura il client SMTP (Gmail) a partire dalle variabili d'ambiente.
/// Per Gmail serve una "App Password" (Account Google → Sicurezza → Password per le app),
/// non la normale password dell'account: Gmail rifiuta l'autenticazione SMTP con quella.
private func configureSmtp(app: Application) throws {
    let SMTP_USERNAME = try requireEnv("SMTP_USERNAME")
    let SMTP_PASSWORD = try requireEnv("SMTP_PASSWORD")

    let SMTP_HOST = Environment.get("SMTP_HOST") ?? "smtp.gmail.com"
    let SMTP_PORT = Environment.get("SMTP_PORT").flatMap(Int.init) ?? 587

    app.smtp.configuration.hostname = SMTP_HOST
    app.smtp.configuration.port = SMTP_PORT
    app.smtp.configuration.signInMethod = .credentials(username: SMTP_USERNAME, password: SMTP_PASSWORD)
    app.smtp.configuration.secure = .startTls

    app.emailService = EmailService(app: app)
    app.logger.notice("[SMTP] Client configurato ed EmailService registrato")
}
