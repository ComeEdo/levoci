# Le Voci — Backend Server (Swift & Vapor)

Backend API ad alte prestazioni per la piattaforma **"Voci di Corridoio"**, riscritto in **Swift** utilizzando il framework **Vapor 4** e l'ORM **Fluent (MySQL/MariaDB)** con supporto per autenticazione Mutual TLS (mTLS).

---

## 📐 Architettura del Progetto

Il progetto adotta un'architettura modulare a livelli (**Layered Architecture**), separando nettamente il trasporto HTTP, la validazione, la persistenza e i servizi di dominio:

```text
levoci/
├── Public/                       # Asset statici serviti via HTTP
│   └── img/                      # Immagini pubbliche (es. voci_di_corridoio_logo.png)
│
├── Resources/                    # Risorse del server (template Leaf)
│   └── Views/                    # Template di visualizzazione
│       ├── Emails/
│       │   └── verificationEmail.leaf # Template email di verifica (HTML escapato)
│       ├── verifyEmail.leaf           # Pagina di conferma verifica email (form POST)
│       ├── verifyEmailInvalid.leaf    # Pagina di errore link non valido o scaduto
│       └── verifyEmailSuccess.leaf    # Pagina di conferma avvenuta verifica email
│
├── Sources/levoci/
│   ├── Controllers/              # Endpoint HTTP e RouteCollection di Vapor
│   │   ├── AuthController.swift       # Registrazione, Login, Refresh, Logout-All
│   │   ├── UserController.swift       # Profilo utente, Upload/Download Avatar
│   │   ├── PostController.swift       # Creazione post, Feed con sincronizzazione delta
│   │   ├── TimetableController.swift  # Consultazione orario scolastico
│   │   ├── ClassController.swift      # Classi scolastiche e indirizzi di studio
│   │   └── WebController.swift        # Pagine web (non API JSON): /emailVerifications flow
│   │
│   ├── DTOs/                     # Data Transfer Objects (Codable & Content)
│   │   ├── AuthDTOs.swift             # Payload richiesta/risposta per autenticazione
│   │   ├── UserDTOs.swift             # DTO profilo utente e raggruppamento per ruolo
│   │   ├── PostDTOs.swift             # DTO creazione post, feed sync e voti
│   │   ├── TimetableDTOs.swift        # DTO orario scolastico, lezioni e materie
│   │   └── ClassDTOs.swift            # DTO classi e indirizzi di studio
│   │
│   ├── Models/                   # Entità Fluent (Mappatura Database MariaDB)
│   │   ├── Credentials.swift          # Tabella `credentials` (email, hash password, tokenVersion)
│   │   ├── User.swift                 # Tabella `users` (anagrafica, ruoli, avatar, userVersion)
│   │   ├── Role.swift                 # Tabella `roles` (Studente, Docente, Personale)
│   │   ├── SchoolClass.swift          # Tabella `classes` (sezione, anno, date validità)
│   │   ├── StudyField.swift           # Tabella `studyFields` (indirizzo es. Informatica)
│   │   ├── Timetable.swift            # Tabella `timetable` (slot orario lezioni)
│   │   ├── Post.swift                 # Tabella `posts` (recensioni e pubblicazioni)
│   │   └── Vote.swift                 # Tabella `votes` (voti numerici e tipologia)
│   │
│   ├── Migrations/               # Migrazioni asincrone dello schema Database
│   │   ├── CreateCredentials.swift    # Creazione tabella `credentials`
│   │   ├── CreateAcademicStructure.swift # Tabelle `roles`, `studyFields`, `classes`, `timetable`
│   │   ├── CreateUsers.swift          # Creazione tabella `users` con foreign keys
│   │   └── CreatePostsAndVotes.swift  # Tabelle `votes` e `posts`
│   │
│   ├── Middlewares/              # Middleware di protezione e autorizzazione
│   │   ├── AuthTokenMiddleware.swift  # Validazione token credenziali (RS256)
│   │   └── UserTokenMiddleware.swift  # Validazione token sessione utente (RS256)
│   │
│   ├── Services/                 # Servizi di business logic disaccoppiati
│   │   ├── TokenService.swift         # Generazione e validazione JWT (RS256 asimmetrico)
│   │   ├── EmailService.swift         # Invio email asincrone di verifica
│   │   └── ImageService.swift         # Ritaglio 1:1, elaborazione e storage avatar
│   │
│   ├── Validation/               # Sanificazione e validazione centralizzata dell'input (vedi sezione Convenzioni)
│   │   ├── Sanitizer.swift            # Trasformazioni pure (trim, NFC, apostrofi, lowercase)
│   │   ├── InputField.swift           # Enum dei campi in input (nome per i messaggi di errore)
│   │   ├── PersonName.swift           # Nome/Cognome validato
│   │   ├── Username.swift             # Username validato (case-sensitive)
│   │   ├── Password.swift             # Password con policy + `hashed(on:)` → `PasswordHash` (pronto per il DB)
│   │   ├── SchoolEmail.swift          # Email istituzionale + ruolo dedotto + SchoolPolicy (dominio)
│   │   ├── VerificationToken.swift    # Token di verifica email (sanitizzazione e lunghezza, mai nei log)
│   │   ├── HTTPURL.swift              # URL HTTP/HTTPS validato con host, normalizzazione ed endpoint
│   │   └── Validatable.swift          # `ValidatableRequest` (DTO, helper `req.validatedBody(...)`) e `ValidatedField`
│   │
│   ├── configure.swift           # Setup DB con mTLS, migrazioni, FileMiddleware e rotte
│   ├── entrypoint.swift          # Entry point asincrono dell'applicazione
│   └── routes.swift              # Registrazione centralizzata delle collezioni di rotte
│
└── Tests/levociTests/            # Suite di test automatizzati (VaporTesting)
    ├── levociTests.swift             # Test delle rotte e dello stato dell'API
    ├── ValidatedFieldsTests.swift    # Test puri sui tipi validati
    ├── ArchitectureRulesTests.swift  # Verifica automatica delle regole architetturali
    └── BcryptPasswordTests.swift     # Test sul limite di 72 byte di Bcrypt
```

---

## ✅ Convenzioni: sanificazione e validazione dell'input

**Regola:** ogni dato che arriva dal client viene sanificato e validato in **un solo posto**, dentro un tipo dedicato al campo. I controller ricevono **solo tipi già validati**, mai stringhe grezze.

**Come funziona**

1. **Un tipo per ogni campo** (cartella `Validation/`): `PersonName`, `Username`, `Password`, `SchoolEmail`. L'unico modo per crearlo è `init(raw:) throws`, che sanifica (trim, NFC, ...) e valida. Se hai in mano un `Username`, è valido per costruzione.
2. **I DTO restano con `String` grezze** (è il formato JSON sul filo) e si conformano a `ValidatableRequest`: il loro `validated()` costruisce i tipi sopra e restituisce un oggetto `Validated` (es. `ValidatedRegistration`).
3. **Il controller legge il body solo con `req.validatedBody(MioDTO.self)`** e usa i valori con `.value` (es. `body.username.value`).

```swift
// DTO (stringhe grezze sul filo)
struct LoginRequestDTO: Content { let email: String; let password: String }

// Oggetto validato che vede il controller
struct ValidatedLogin: Sendable { let email: SchoolEmail; let password: LoginPassword }

extension LoginRequestDTO: ValidatableRequest {
    func validated() throws -> ValidatedLogin {
        ValidatedLogin(email: try SchoolEmail(raw: email), password: try LoginPassword(raw: password))
    }
}

// Controller
let body = try req.validatedBody(LoginRequestDTO.self)
```

**Checklist per un nuovo endpoint con body**

- [ ] Il campo ha già un tipo in `Validation/`? Riusalo. Altrimenti crea un nuovo tipo con `init(raw:) throws` (non copiare regole in un DTO).
- [ ] Il DTO si conforma a `ValidatableRequest` e ha il suo oggetto `Validated`.
- [ ] Il controller usa `req.validatedBody(...)`, mai `req.content.decode(...)`.
- [ ] Test puri per le regole nuove in `ValidatedFieldsTests`.

**Decisioni di progetto da non rompere**

- `Username` è **case-sensitive**: non applicare `lowercased()`.
- `Password.minLength` è una **costante fissa nel codice** (`Password.swift`), non una variabile d'ambiente.
- Al **login** non si applica la policy sulla password (serve un tipo a parte, es. `LoginPassword`, che richiede solo "non vuota"): altrimenti si bloccherebbero le password create con regole precedenti.

`ArchitectureRulesTests` fa fallire la suite se un controller usa `content.decode(`, `content.get(`, `query.decode(` o `query.get(`.

---

## 🗺️ Mappatura delle API

| Metodo | Endpoint | Controller | Protezione | Descrizione |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/health` | Base | Pubblico | Health check dell'API |
| `GET` | `/img/*` | `FileMiddleware` | Pubblico | Asset statici (logo app, immagini pubbliche) |
| `POST` | `/auth/registrations` | `AuthController` | Pubblico | Registrazione nuovo utente e credenziali |
| `GET` | `/emailVerifications?token=...` | `WebController` | Pubblico | Valida il link (GET idempotente), setta cookie HttpOnly temporaneo e reindirizza (`303`) a `/emailVerifications/confirm` |
| `GET` | `/emailVerifications/confirm` | `WebController` | Pubblico | Pagina di conferma con pulsante per eseguire la POST di verifica |
| `POST` | `/emailVerifications/confirm` | `WebController` | Pubblico | Consuma il token dal cookie HttpOnly, valida `tokenVersion`, imposta `isEmailVerified = true` su DB, elimina il cookie e reindirizza (`303`) a `/emailVerifications/success` |
| `GET` | `/emailVerifications/success` | `WebController` | Pubblico | Pagina di conferma avvenuta verifica email |
| `POST` | `/usernames/availability` | `AuthController` | Pubblico | Verifica disponibilità username (204 se disponibile, 409 se occupato) |
| `POST` | `/login` | `AuthController` | Pubblico | Login con email/password, restituisce `authToken` e profili |
| `GET` | `/auth/session` | `AuthController` | `AuthToken` | Verifica stato e validità dell'AuthToken |
| `POST` | `/auth/getTokenAndUser` | `AuthController` | `AuthToken` | Rilascia `userToken` per il profilo utente selezionato |
| `POST` | `/auth/refreshAuthToken` | `AuthController` | `AuthToken` | Refresh dell'AuthToken (valido dopo 24h dall'emissione) |
| `DELETE` | `/auth/sessions` | `AuthController` | `AuthToken` | Rigenera `tokenVersion` su `credentials` invalidando tutti i dispositivi |
| `GET` | `/user/isUserTokenValid` | `UserController` | `UserToken` | Verifica validità dello UserToken |
| `GET` | `/user/refreshUserToken` | `UserController` | `UserToken` | Refresh dello UserToken (valido dopo 10 min dall'emissione) |
| `POST` | `/user/profileImage` | `UserController` | `UserToken` | Upload immagine profilo con ritaglio 1:1 |
| `DELETE` | `/user/profileImage` | `UserController` | `UserToken` | Eliminazione immagine profilo utente |
| `GET` | `/user/:userUUID/profileImage` | `UserController` | `UserToken` | Download immagine profilo per UUID specificato |
| `GET` | `/user/getTimetable` | `TimetableController` | `UserToken` | Orario scolastico per classe o docente corrente |
| `GET` | `/user/post` | `PostController` | `UserToken` | Feed dei post con supporto delta-sync (`?lastSync=...`) |
| `POST` | `/user/post` | `PostController` | `UserToken` | Creazione post con voto (per docente, materia o ora) |
| `GET` | `/classes/info` | `ClassController` | Pubblico | Elenco classi attive dell'istituto |
| `GET` | `/classes/registration` | `ClassController` | Pubblico | Classi aperte alla registrazione degli studenti |

---

## 🔐 Autenticazione Database MariaDB via Mutual TLS (mTLS / Two-Way)

La connessione al database MariaDB utilizza **autenticazione a certificati digitali (Two-Way TLS)** senza password:
1. **CA del Database** (`DATABASE_CA_CERT_PATH`): verifica l'identità del server MariaDB.
2. **Certificato Client** (`DATABASE_CLIENT_CERT_PATH`): identifica il backend Swift presso MariaDB.
3. **Chiave Privata Client** (`DATABASE_CLIENT_KEY_PATH`): firma la connessione client TLS.
4. **Nessuna Password**: il campo `password` è impostato su stringa vuota, poiché MariaDB valida l'accesso tramite il Subject o l'Issuer del certificato X.509 (`REQUIRE X509` / `REQUIRE SUBJECT`).

---

## 🌐 Infrastruttura: Apache come Reverse Proxy & SSL/TLS

L'architettura di produzione prevede **Apache** esposto su porta 443 (HTTPS) che gestisce la cifratura SSL/TLS esterna (TLS Termination) e inoltra le richieste in HTTP locale all'applicazione Swift in esecuzione su porta 8080 (`127.0.0.1:8080`).

```apache
<VirtualHost *:443>
    ServerName api.tuodominio.it

    # Gestione SSL / Let's Encrypt in Apache
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/api.tuodominio.it/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/api.tuodominio.it/privkey.pem

    # Header fondamentali per il reverse proxy
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"

    # Servire file statici direttamente con Apache
    Alias /img /var/www/levoci/Public/img
    <Directory /var/www/levoci/Public/img>
        Require all granted
    </Directory>

    # Inoltro a Swift Vapor
    ProxyPass / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/

    # Privacy dei log: esclude i token di verifica email dai log di accesso Apache
    SetEnvIf Request_URI "^/emailVerifications" dontlog
    CustomLog /var/log/apache2/levoci_access.log combined env=!dontlog
</VirtualHost>
```

---

## ⚙️ Variabili d'Ambiente (`.env`)

```env
# Server
PORT=8080
ENVIRONMENT=development

# Database MariaDB (Two-Way SSL / mTLS Authentication - No Password)
DATABASE_HOST=127.0.0.1
DATABASE_PORT=3306
DATABASE_USERNAME=app_user_levoci
DATABASE_NAME=levoci
DATABASE_CA_CERT_PATH=/path/to/ca-cert.pem
DATABASE_CLIENT_CERT_PATH=/path/to/client-cert.pem
DATABASE_CLIENT_KEY_PATH=/path/to/client-key.pem
DATABASE_TLS_VERIFY=true

# URL pubblico (quello visibile agli utenti, cioè Apache) usato nei link delle email di verifica.
# Dietro Apache l'app ascolta su 127.0.0.1:8080, quindi in produzione va impostato SEMPRE (es. https://tuodominio.it).
# Se manca, in produzione l'app non parte; negli altri ambienti usa l'indirizzo di bind con un warning.
# In produzione deve essere https: lo schema decide anche l'attributo `Secure` dei cookie (HTTPURL.isSecure).
PUBLIC_BASE_URL=https://tuodominio.it

# JWT RS256 Keys
JWT_PRIVATE_KEY_PATH=/path/to/private.pem
JWT_PUBLIC_KEY_PATH=/path/to/public.pem

# SMTP / Email Service
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USERNAME=corridoio.delle.voci@gmail.com
SMTP_PASSWORD=
EMAIL_FROM=corridoio.delle.voci@gmail.com

# Storage
AVATAR_STORAGE_DIR=/var/data/levoci/users
```

---

## 🚀 Avvio e Sviluppo

### In Xcode
1. Apri la cartella del progetto in Xcode (`File > Open... > levoci`).
2. Seleziona lo schema **levoci** e come Run Destination **My Mac**.
3. Premi **Cmd + R** per compilare ed avviare, oppure **Cmd + U** per eseguire i test automatici.

### Da Terminale (Swift CLI)
```bash
# Compilazione del progetto
swift build

# Esecuzione delle migrazioni del Database
swift run levoci migrate

# Avvio del server
swift run levoci serve --hostname 127.0.0.1 --port 8080
```

### Esecuzione Test
```bash
swift test
```
