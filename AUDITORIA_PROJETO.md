# Relatório de Auditoria - Gestión Duarte

**Data:** 11/03/2025  
**Escopo:** Autenticação via Google Sheets, relatórios por e-mail, notificações Push (Firebase)

---

## 1. Configuração Android & Firebase

| Item | Status | Observação |
|------|--------|------------|
| `applicationId` | OK | `com.project.gestion` em `android/app/build.gradle.kts` |
| `namespace` | OK | `com.project.gestion` |
| `com.google.gms.google-services` | Corrigido | Sintaxe Kotlin DSL: `apply(plugin = "com.google.gms.google-services")` |
| Estrutura Kotlin | OK | `android/app/src/main/kotlin/com/project/gestion/MainActivity.kt` presente |

---

## 2. Inicialização do App (Flutter)

| Item | Status | Observação |
|------|--------|------------|
| `WidgetsFlutterBinding.ensureInitialized()` | OK | Chamado no início de `main()` |
| `Firebase.initializeApp()` | OK | Usa `DefaultFirebaseOptions.currentPlatform` |
| `main() async` | OK | Função assíncrona correta |

---

## 3. Lógica de Notificação e Login

| Item | Status | Observação |
|------|--------|------------|
| `requestPermission` | OK | Em `PushNotificationService.registrarDispositivo` |
| Captura Token FCM | OK | `_fcm.getToken()` |
| Envio para Web App | OK | Usa GET+base64 (evita CORS), ação `atualizarToken` |
| Chamada pós-login | OK | `PushNotificationService.registrarDispositivo(email)` após validação |

---

## 4. Google Apps Script (Back-end)

### 4.1 doGet / doPost

| Ação | Tratamento | Observação |
|------|------------|------------|
| **login** | doGet | Validado em `loginUsuario()` com aba 'Usuarios' (e-mail, senha) |
| **atualizarToken** | doGet (payload) + doPost | Salva em FCM_Tokens e na col K (Token_FCM) de Usuarios quando existir |

### 4.2 processarRelatoriosAgendados()

| Item | Status | Correção aplicada |
|------|--------|-------------------|
| Filtro status 'Resuelto' | OK | `dEstatus.toLowerCase() === "resuelto"` → excluído |
| Respeito a perfil (Ejecutor, Gerente, Coordinador, Director) | OK | Regras por perfil implementadas |
| Trava 'Informe de Demandas' (col H) | OK | `user.querInforme === true` |
| Range de demandas | Corrigido | Antes: `lastRowDem - 6` (cortava linhas). Corrigido para `lastRowDem` |

### 4.3 enviarNotificacaoPush()

| Item | Status | Observação |
|------|--------|------------|
| Função | Implementada | Envia via FCM Legacy API |
| FIREBASE_SERVER_KEY | Necessário | Configurar em Propriedades do script: `Script Properties > FIREBASE_SERVER_KEY` |
| Filtro Coordenadores | OK | Apenas perfil Coordinador/Coordenador |
| Filtro por setor | OK | `sectorDestino` opcional |

---

## 5. Integridade da Planilha

### Aba Usuarios

| Coluna | Esperado | Código |
|--------|----------|--------|
| Senha | C | Busca dinâmica por alias (senha, password, contraseña) |
| Email | D | Busca dinâmica por alias |
| Perfil | G | `row[6]` em processarRelatorios; busca dinâmica em login |
| Informe de Demandas | H | `row[7]` (index 7) |
| Frequência | J | `row[9]` |
| Token_FCM | K | `atualizarTokenFCM` grava na coluna Token_FCM quando existir |

### Aba Respuestas del Form

| Item | Esperado | Código |
|------|----------|--------|
| Cabeçalho | Linha 6 | `HEADER_ROW = 6` |
| Dados | Linha 7+ | `DATA_START_ROW = 7` |
| Status Actual | Col Q (índice 16) | `d[16]` em processarRelatorios |

**Atenção:** O script usa mapeamento dinâmico (COL_ALIASES) para colunas em Respuestas. Índices fixos em `processarRelatoriosAgendados` (d[2], d[4], d[5], d[6], d[9], d[11], d[16]) assumem ordem específica; se as colunas da planilha forem alteradas, será necessário ajustar.

---

## 6. Correções Aplicadas

1. **android/app/build.gradle.kts** – Sintaxe do plugin Google Services corrigida para Kotlin DSL.
2. **android/build.gradle.kts** – `buildscript` ajustado (repositories + classpath em Kotlin).
3. **script_gestao_duarte.js** – `getRange(7, 1, lastRowDem - 6, ...)` corrigido para `lastRowDem` (removido `- 6`).
4. **script_gestao_duarte.js** – Função `atualizarTokenFCM` implementada (não existia) e gravação na col K de Usuarios adicionada.
5. **script_gestao_duarte.js** – Tratamento de `atualizarToken` no `doGet` (payload base64), pois o Flutter usa GET.
6. **script_gestao_duarte.js** – Função `enviarNotificacaoPush(sectorDestino, titulo, mensagem)` implementada.

---

## 7. Pendências / Próximos Passos

1. **Configurar FIREBASE_SERVER_KEY** no Apps Script:  
   Extensões > Apps Script > Configurações do projeto > Propriedades do script > Adicionar `FIREBASE_SERVER_KEY` com a chave de servidor do Firebase.

2. **Chamar enviarNotificacaoPush** em pontos adequados, por exemplo:
   - Ao salvar/reprogramar uma demanda (trigger `onEdit` ou função chamada após `salvarDemanda`).
   - No `processarRelatoriosAgendados`, se desejar enviar push além de e-mail.

3. **Garantir aba Usuarios** com colunas coerentes, por exemplo:  
   `ID | Nombre | Senha | Email | Area | Sector | Perfil | Informe | ... | Frequencia | Token_FCM`.

4. **Testar push notifications** em dispositivo Android real após login e registro do token.
