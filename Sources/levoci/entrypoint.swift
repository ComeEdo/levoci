import Vapor
import MySQLKit
import Logging
import Fluent
import SQLKit

@main
enum Entrypoint {
    static func main() async throws {
        loadEnvironmentVariables()

        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = try await Application.make(env)

        do {
            try await configure(app)
            try await verifyDatabase(app: app)

            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            exit(1)
        }
        try await app.asyncShutdown()
    }

    /// Esegue una diagnostica approfondita della connessione al database MariaDB
    private static func verifyDatabase(app: Application) async throws {
        guard let sql = app.db as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Il driver del database non è conforme a SQLDatabase")
        }

        let start = Date()
        do {
            let rows = try await sql.raw("""
                SELECT 
                    DATABASE() AS current_db, 
                    USER() AS db_user, 
                    VERSION() AS db_version
            """).all()

            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

            guard let firstRow = rows.first else {
                throw Abort(.internalServerError, reason: "Nessuna risposta dal server MariaDB")
            }

            let dbName = (try? firstRow.decode(column: "current_db", as: String.self)) ?? "sconosciuto"
            let dbUser = (try? firstRow.decode(column: "db_user", as: String.self)) ?? "sconosciuto"
            let dbVersion = (try? firstRow.decode(column: "db_version", as: String.self)) ?? "sconosciuta"

            let tableRows = try await sql.raw("""
                SELECT COUNT(*) AS total_tables 
                FROM information_schema.tables 
                WHERE table_schema = DATABASE()
            """).all()
            let totalTables = (try? tableRows.first?.decode(column: "total_tables", as: Int.self)) ?? 0

            app.logger.notice("[Database] Connessione stabilita con successo in \(elapsedMs) ms")
            app.logger.notice("[Database] Server: \(dbVersion) | Database: \(dbName) | Utente: \(dbUser)")
            app.logger.notice("[Database] Schema: \(totalTables) tabelle verificate")
        } catch {
            let host = try requireEnv("DATABASE_HOST")
            let port = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? MySQLConfiguration.ianaPortNumber
            app.logger.critical("[Database] Impossibile connettersi a MariaDB (\(host):\(port))")
            app.logger.critical("[Database] Errore: \(error.localizedDescription)")

            let errorDesc = String(describing: error)
            if errorDesc.contains("errno: 65") || errorDesc.contains("No route to host") {
                app.logger.critical("[Database] Host non raggiungibile (\(host):\(port))")
            } else if errorDesc.contains("errno: 61") || errorDesc.contains("Connection refused") {
                app.logger.critical("[Database] Connessione rifiutata sulla porta \(port). Verificare lo stato del servizio MariaDB")
            } else if errorDesc.contains("Access denied") {
                app.logger.critical("[Database] Autenticazione fallita. Verificare credenziali e certificati TLS nel file .env")
            }

            throw error
        }
    }

    /// Carica le variabili da .env nell'ambiente di processo prima dell'inizializzazione del logger
    private static func loadEnvironmentVariables() {
        let candidatePaths = [
            ".env",
            FileManager.default.currentDirectoryPath + "/.env"
        ]
        
        for path in candidatePaths {
            guard let data = FileManager.default.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }
            for rawLine in content.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let separator = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                var val = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                    val = String(val.dropFirst().dropLast())
                }
                unsafe setenv(key, val, 0)
            }
            break
        }
    }
}
