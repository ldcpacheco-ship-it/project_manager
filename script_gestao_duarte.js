/**
 * GESTÃO DUARTE - API UNIFICADA (FLUTTER + GOOGLE SHEETS)
 * Versão: 1.3 - Correção de Mapeamento de Colunas e Carimbo de Data
 */

// --- CONSTANTES ABA "Respuestas del Form" ---
var HEADER_ROW = 6;
var DATA_START_ROW = HEADER_ROW + 1;
var SHEET_DEMANDAS = "Respuestas del Form";

// --- ALIASES DE COLUNAS (compatíveis com "Respuestas del Form") ---
var COL_ALIASES = {
  tema: ['requerimiento', 'tema', 'título', 'titulo', 'tipo de demanda'],
  sector: ['secctor solicitante', 'sector solicitante', 'sector', 'setor', 'setor solicitante'],
  sector_destino: ['sector de destino', 'sector destino', 'destino', 'setor destino', 'setor de destino', 'área de destino', 'area de destino'],
  solicitante: ['solicitante', 'nombre', 'nome solicitante'],
  email_solicitante: ['email_solicitante', 'email solicitante', 'correo solicitante', 'e-mail solicitante'],
  requerimiento: ['requerimiento', 'requisito', 'descripcion'],
  responsable: ['responsable', 'responsavel', 'responsable asignado'],
  fecha_necesaria: ['fecha necesaria', 'fecha necessaria', 'fecha', 'date'],
  hora: ['hora necessaria', 'hora necesaria', 'hora inicio', 'hora', 'time'],
  duracion: ['duracion estimada', 'duración', 'duracion'],
  status: ['estatus actual', 'status', 'estado', 'estatus'],
  brigada: ['brigada topografica', 'brigada', 'equipe'],
  local: ['local', 'localización', 'localizacion', 'ubicación', 'ubicacion', 'lugar', 'ubicacion del servicio', 'dirección', 'direccion'],
  prioridad: ['prioridad', 'prioridade', 'rank', 'orden'],
  tipo: ['tipo de demanda', 'tipo demanda', 'tipo'],
  coordenada: ['coordenadas', 'coordenada', 'coord'],
  hora_fin: ['hora fin', 'hora término', 'horafin'],
  id_anterior: ['id anterior', 'referencia', 'reprogramada']
};

function buildHeaderMap(header) {
  var m = {};
  if (!header || !header.length) return m;
  for (var h = 0; h < header.length; h++) {
    var n = String(header[h] || '').trim().toLowerCase();
    if (!n) continue;
    for (var key in COL_ALIASES) {
      if (COL_ALIASES.hasOwnProperty(key)) {
        for (var a = 0; a < COL_ALIASES[key].length; a++) {
          if (n.indexOf(COL_ALIASES[key][a]) >= 0 || COL_ALIASES[key][a].indexOf(n) >= 0) {
            // Evitar que "Carimbo de data/hora" (col. A) seja mapeada como "Hora Necessaria"
            if (key === 'hora' && n.indexOf('carimbo') >= 0) break;
            // Nunca mapear "Estatus Técnico" ou "Situación" como status; usar apenas "Estatus Actual"
            if (key === 'status' && (n.indexOf('técnico') >= 0 || n.indexOf('tecnico') >= 0 || n.indexOf('situación') >= 0 || n.indexOf('situacion') >= 0)) break;
            if (m[key] === undefined) m[key] = h;
            break;
          }
        }
      }
    }
  }
  return m;
}

function getCol(hdrMap, keys) {
  if (!keys || !keys.length) return -1;
  for (var k = 0; k < keys.length; k++) {
    var idx = hdrMap[keys[k]];
    if (idx !== undefined && idx >= 0) return idx;
  }
  return -1;
}

/** Retorna o índice da coluna "Hora Necessaria" (nunca coluna 0 Carimbo). Fallback: coluna H = índice 7. */
function getColHoraNecessaria(header) {
  if (!header || !header.length) return 7;
  for (var i = 0; i < header.length; i++) {
    var n = String(header[i] || '').trim().toLowerCase();
    if (!n || n.indexOf('carimbo') >= 0) continue;
    if (n.indexOf('hora necessaria') >= 0 || n.indexOf('hora necesaria') >= 0 || n.indexOf('hora inicio') >= 0)
      return i;
  }
  return 7;
}

/** Retorna o valor de dados para uma chave de COL_ALIASES. Hora e tema com prioridade; demais com fallbacks. */
function getDadosVal(key, dados) {
  var v = '';
  if (key === 'hora') {
    v = dados.hora || dados.hora_inicio || '';
  } else if (key === 'tema') {
    v = dados.tipo_demanda || dados.tipoDemanda || dados.tema || 'Nueva demanda';
  } else if (key === 'status') {
    v = (dados.status && String(dados.status).trim() !== '') ? String(dados.status).trim() : 'No Programada';
  } else if (key === 'sector') {
    v = dados.sectorSolicitante || dados.sector || '';
  } else if (key === 'sector_destino') {
    v = dados.sectorDestino || dados.sector_destino || '';
  } else if (key === 'tipo') {
    v = dados.tipo_demanda || dados.tipoDemanda || dados.tema || '';
  } else if (key === 'fecha_necesaria') {
    v = dados.fecha_necesaria || dados.fechaNecesaria || '';
  } else if (key === 'requerimiento') {
    v = dados.requerimiento || '';
  } else if (key === 'local') {
    v = dados.local || '';
  } else if (key === 'solicitante') {
    v = dados.solicitante || '';
  } else if (key === 'responsable') {
    v = dados.responsable || '';
  } else if (key === 'duracion') {
    v = dados.duracion || '';
  } else if (key === 'coordenada') {
    v = dados.coordenadas || dados.coordenada || '';
  } else if (key === 'hora_fin') {
    v = dados.horaFin || dados.hora_fin || '';
  } else if (key === 'id_anterior') {
    v = dados.idDemandaAnterior || dados.id_anterior || '';
  } else {
    v = dados[key] || '';
  }
  return v;
}

// --- 1. PORTA DE ENTRADA (Comunicação com Flutter) ---

function doGet(e) {
  var param = e && e.parameter ? e.parameter : {};
  var action = param.action != null ? String(param.action).trim() : null;
  if (Array.isArray(action)) action = (action[0] || '').trim();
  try {
    // Si hay payload, intentar despachar por decoded.action (no depender del action en la URL)
    if (param.payload) {
      var payloadStr = (param.payload || '').replace(/-/g, '+').replace(/_/g, '/');
      if (payloadStr) {
        try {
          var decoded = JSON.parse(Utilities.newBlob(Utilities.base64Decode(payloadStr)).getDataAsString());
          var act = (decoded.action || action || '').toString().trim();
          if (act === 'solicitarResetSenha') {
            return solicitarResetSenha((decoded.email || '').toString().trim().toLowerCase());
          }
          if (act === 'confirmarResetSenha') {
            return confirmarResetSenha(decoded.email || '', decoded.codigo || '', decoded.novaSenha || '');
          }
          if (act === 'alterarSenha') {
            return alterarSenha(decoded.email || '', decoded.senhaAtual || '', decoded.novaSenha || '');
          }
        } catch (err) {}
      }
    }
    if (action == 'login') {
      var email = e.parameter.email || e.parameter.correo;
      var senha = e.parameter.password || e.parameter.senha;
      return loginUsuario(email, senha);
    }
    
    // Diagnóstico: chame com ?action=loginDebug&email=seu@email.com
    if (action == 'loginDebug') {
      var email = e.parameter.email || e.parameter.correo;
      return loginDebug(email);
    }
    
    if (action == 'executarAutomacao') {
      processarPrioridadesOrdenacao();
      return responderPadrao(true, "Prioridades ordenadas con éxito.", null);
    }

    if (action == 'getDemandas') {
      var sector = e.parameter.sector || '';
      var email = e.parameter.email || '';
      var perfil = e.parameter.perfil || '';
      var responsable = e.parameter.responsable || e.parameter.nombre || '';
      return getDemandas(sector, email, perfil, responsable);
    }
    if (action == 'getDemandasDebug') {
      var sector = e.parameter.sector || 'Topografía';
      return getDemandasDebug(sector);
    }
    if (action == 'getDemandasGestion') {
      var sector = e.parameter.sector || '';
      var perfil = e.parameter.perfil || '';
      var email = e.parameter.email || '';
      var responsable = e.parameter.responsable || e.parameter.nombre || '';
      return getDemandasGestion(sector, perfil, email, responsable);
    }
    if (action == 'getDemandasAgenda') {
      var sector = e.parameter.sector || '';
      var email = e.parameter.email || '';
      var perfil = e.parameter.perfil || '';
      var responsable = e.parameter.responsable || e.parameter.nombre || '';
      return getDemandasAgenda(sector, email, perfil, responsable);
    }
    if (action == 'getKPIs') {
      var sector = e.parameter.sector || '';
      return getKPIs(sector);
    }
    if (action == 'getLocais') {
      return getLocais();
    }
    if (action == 'verificarDisponibilidad') {
      var dataHora = e.parameter.dataHora || '';
      return verificarDisponibilidad(dataHora);
    }
    if (action == 'getOcupacaoBrigadas') {
      var sector = e.parameter.sector || '';
      return getOcupacaoBrigadas(sector);
    }
    // Flutter Web: usa GET com payload base64url para evitar CORS
    if (action == 'salvarDemanda' || action == 'reprogramarDemanda' || action == 'crearDemandaCancelada') {
      var payload = (e.parameter.payload || '').replace(/-/g, '+').replace(/_/g, '/');
      if (!payload) return responderPadrao(false, "Falta payload", null);
      try {
        var decoded = Utilities.newBlob(Utilities.base64Decode(payload)).getDataAsString();
        var data = JSON.parse(decoded);
        var dados = data.dados || {};
        if (action == 'salvarDemanda') return salvarDemanda(dados);
        if (action == 'reprogramarDemanda') return reprogramarDemanda(dados);
        if (action == 'crearDemandaCancelada') return crearDemandaCancelada(dados);
      } catch (err) {
        return responderPadrao(false, "Payload inválido: " + err.toString(), null);
      }
    }

    return responderPadrao(false, "Acción no válida", null);
  } catch (error) {
    return responderPadrao(false, error.toString(), null);
  }
}

function doPost(e) {
  try {
    // Aceita JSON de: postData.contents (text/plain, application/json) ou e.parameter.body (form-urlencoded, evita CORS no Flutter Web)
    var body = null;
    if (e && e.parameter && e.parameter.body) {
      body = e.parameter.body;  // form-urlencoded - não dispara preflight CORS
    } else if (e && e.postData && e.postData.contents) {
      body = e.postData.contents;
    }
    var data = body ? JSON.parse(body) : {};
    var action = data.action || (e && e.parameter ? e.parameter.action : null);
    if (action === 'crearDemanda' || action === 'salvarDemanda') {
      var dados = data.dados || {};
      return salvarDemanda(dados);
    }
    if (action === 'crearDemandaReprogramada' || action === 'reprogramarDemanda') {
      var dados = data.dados || {};
      return reprogramarDemanda(dados);
    }
    if (action === 'crearDemandaCancelada') {
      var dados = data.dados || {};
      return crearDemandaCancelada(dados);
    }
    return responderPadrao(false, "Acción POST no válida", null);
  } catch (err) {
    return responderPadrao(false, err.toString(), null);
  }
}

// --- 2. LÓGICA DE USUÁRIO E ACESSO ---
// Aba "Usuarios": ID | Nombre | senha | email | Area | Perfil

function loginUsuario(emailBuscado, senhaRecebida) {
  var emailNorm = emailBuscado ? String(emailBuscado).trim().toLowerCase() : '';
  var senhaNorm = senhaRecebida ? String(senhaRecebida).trim() : '';
  if (!emailNorm) {
    return responderPadrao(false, "Por favor, ingrese su correo.", null);
  }
  if (!senhaNorm) {
    return responderPadrao(false, "Por favor, ingrese su contraseña.", null);
  }

  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName("Usuarios") || ss.getSheetByName("Usuários");
  if (!sheet) {
    for (var si = 0; si < ss.getSheets().length; si++) {
      if (ss.getSheets()[si].getName().toLowerCase().indexOf("usuario") >= 0) {
        sheet = ss.getSheets()[si];
        break;
      }
    }
  }
  if (!sheet) {
    return responderPadrao(false, "Hoja 'Usuarios' no encontrada.", null);
  }

  var data = sheet.getDataRange().getValues();
  var header = data[0];
  
  // Buscar índices: Usuarios usa ID | Nombre | senha | email | Area | Perfil
  var colEmail = -1;
  var colSenha = -1;
  for (var h = 0; h < header.length; h++) {
    var nomeCol = String(header[h] || '').trim().toLowerCase();
    if (colEmail === -1 && (nomeCol === 'email' || nomeCol === 'correo' || nomeCol === 'e-mail' || nomeCol.indexOf('email') >= 0 || nomeCol.indexOf('correo') >= 0)) {
      colEmail = h;
    }
    if (colSenha === -1 && (nomeCol === 'senha' || nomeCol === 'password' || nomeCol === 'contraseña' || nomeCol.indexOf('senha') >= 0 || nomeCol.indexOf('password') >= 0 || nomeCol.indexOf('contraseña') >= 0)) {
      colSenha = h;
    }
  }
  
  if (colEmail === -1) {
    return responderPadrao(false, "Columna Email no encontrada en la hoja.", null);
  }
  if (colSenha === -1) {
    return responderPadrao(false, "Columna Contraseña no encontrada en la hoja.", null);
  }

  for (var i = 1; i < data.length; i++) {
    var emailCelula = String(data[i][colEmail] || '').toLowerCase().trim().replace(/\s+/g, ' ');
    
    if (emailCelula === emailNorm) {
      var senhaCelula = String(data[i][colSenha] || '').trim();
      
      if (senhaCelula === senhaNorm) {
        var userObj = {};
        for (var idx = 0; idx < header.length; idx++) {
          userObj[header[idx]] = data[i][idx];
        }
        return responderPadrao(true, "", { usuario: userObj });
      } else {
        return responderPadrao(false, "Contraseña incorrecta.", null);
      }
    }
  }
  return responderPadrao(false, "Usuario no encontrado en la base de datos.", null);
}

/** Altera a senha do usuário na aba Usuarios. email, senhaAtual (confirmação), novaSenha. */
function alterarSenha(emailBuscado, senhaAtual, novaSenha) {
  var emailNorm = emailBuscado ? String(emailBuscado).trim().toLowerCase() : '';
  var atual = senhaAtual ? String(senhaAtual).trim() : '';
  var nova = novaSenha ? String(novaSenha).trim() : '';
  if (!emailNorm) return responderPadrao(false, "No se ha indicado el correo.", null);
  if (!atual) return responderPadrao(false, "Indique la contraseña actual.", null);
  if (!nova) return responderPadrao(false, "Indique la nueva contraseña.", null);

  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName("Usuarios") || ss.getSheetByName("Usuários");
  if (!sheet) {
    for (var si = 0; si < ss.getSheets().length; si++) {
      if (ss.getSheets()[si].getName().toLowerCase().indexOf("usuario") >= 0) {
        sheet = ss.getSheets()[si];
        break;
      }
    }
  }
  if (!sheet) return responderPadrao(false, "Hoja 'Usuarios' no encontrada en la base de datos.", null);

  var data = sheet.getDataRange().getValues();
  var header = data[0];
  var colEmail = -1;
  var colSenha = -1;
  for (var h = 0; h < header.length; h++) {
    var nomeCol = String(header[h] || '').trim().toLowerCase();
    if (colEmail === -1 && (nomeCol === 'email' || nomeCol === 'correo' || nomeCol.indexOf('email') >= 0 || nomeCol.indexOf('correo') >= 0)) colEmail = h;
    if (colSenha === -1 && (nomeCol === 'senha' || nomeCol === 'password' || nomeCol === 'contraseña' || nomeCol.indexOf('senha') >= 0 || nomeCol.indexOf('password') >= 0)) colSenha = h;
  }
  if (colEmail === -1) return responderPadrao(false, "Columna Email no encontrada.", null);
  if (colSenha === -1) return responderPadrao(false, "Columna Contraseña no encontrada.", null);

  for (var i = 1; i < data.length; i++) {
    var emailCelula = String(data[i][colEmail] || '').toLowerCase().trim();
    if (emailCelula !== emailNorm) continue;
    var senhaCelula = String(data[i][colSenha] || '').trim();
    if (senhaCelula !== atual) return responderPadrao(false, "Contraseña actual incorrecta.", null);
    var rowSheet = i + 1;
    sheet.getRange(rowSheet, colSenha + 1).setValue(nova);
    return responderPadrao(true, "Contraseña actualizada correctamente.", null);
  }
  return responderPadrao(false, "Usuario no encontrado.", null);
}

// --- Recuperación de contraseña (código por correo) ---
var RESET_SHEET_NAME = 'ResetSenha';
var RESET_CODE_VALID_MINUTES = 15;

function getOrCreateResetSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(RESET_SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(RESET_SHEET_NAME);
    sheet.appendRow(['Email', 'Codigo', 'FechaHora']);
    sheet.getRange(1, 1, 1, 3).setFontWeight('bold');
  }
  return sheet;
}

/** Solicita restablecer contraseña: verifica email en Usuarios, genera código, guarda en ResetSenha, envía correo. */
function solicitarResetSenha(emailBuscado) {
  var emailNorm = emailBuscado ? String(emailBuscado).trim().toLowerCase() : '';
  if (!emailNorm) return responderPadrao(false, "Indique su correo electrónico.", null);

  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheetUsu = ss.getSheetByName("Usuarios") || ss.getSheetByName("Usuários");
  
  // Lógica de búsqueda de hoja (Mantenemos tu código inteligente)
  if (!sheetUsu) {
    for (var si = 0; si < ss.getSheets().length; si++) {
      if (ss.getSheets()[si].getName().toLowerCase().indexOf("usuario") >= 0) {
        sheetUsu = ss.getSheets()[si];
        break;
      }
    }
  }
  if (!sheetUsu) return responderPadrao(false, "Hoja 'Usuarios' no encontrada.", null);

  var data = sheetUsu.getDataRange().getValues();
  var header = data[0];
  var colEmail = -1;
  
  // Buscar columna de email
  for (var h = 0; h < header.length; h++) {
    var n = String(header[h] || '').trim().toLowerCase();
    if (n === 'email' || n === 'correo' || n.indexOf('email') >= 0 || n.indexOf('correo') >= 0) {
      colEmail = h;
      break;
    }
  }
  
  if (colEmail === -1) return responderPadrao(false, "Columna de correo electrónico no encontrada.", null);

  var existe = false;
  for (var i = 1; i < data.length; i++) {
    if (String(data[i][colEmail] || '').toLowerCase().trim() === emailNorm) {
      existe = true;
      break;
    }
  }
  
  if (!existe) return responderPadrao(false, "No hay ninguna cuenta registrada con ese correo.", null);

  // Generación de código de 6 dígitos
  var codigo = String(Math.floor(100000 + Math.random() * 900000));
  var ahora = new Date();
  
  // IMPORTANTE: Asegúrate de que la función getOrCreateResetSheet() exista en tu script
  var sheetReset = getOrCreateResetSheet();
  sheetReset.appendRow([emailNorm, codigo, ahora]);

  try {
    MailApp.sendEmail({
      to: emailNorm,
      subject: "Gestión Duarte – Código de Verificación",
      htmlBody: "<h3>Restablecer Contraseña</h3>" +
                "<p>Su código de verificación es: <b style='font-size: 20px; color: #2D6A4F;'>" + codigo + "</b></p>" +
                "<p>Este código es válido por tiempo limitado.</p>" +
                "<p>Si no solicitó este código, ignore este mensaje.</p>"
    });
  } catch (err) {
    // Si falla el envío, eliminamos la fila para no dejar basura
    if (sheetReset.getLastRow() > 0) {
      sheetReset.deleteRow(sheetReset.getLastRow());
    }
    return responderPadrao(false, "Error al enviar el correo. Detalles: " + err.toString(), null);
  }
  
  return responderPadrao(true, "Si el correo está registrado, recibirá un código de verificación.", null);
}

/** Verificación de Funciones Auxiliares */
function getOrCreateResetSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var name = "Resets";
  var sheet = ss.getSheetByName(name);
  if (!sheet) {
    sheet = ss.insertSheet(name);
    sheet.appendRow(["Email", "Codigo", "Fecha"]);
  }
  return sheet;
}

function responderPadrao(sucesso, mensagem, dados) {
  return {
    success: sucesso,
    message: mensagem,
    data: dados
  };
}


/** Confirma restablecimiento: valida código y actualiza contraseña en Usuarios. */
function confirmarResetSenha(emailBuscado, codigo, novaSenha) {
  var emailNorm = emailBuscado ? String(emailBuscado).trim().toLowerCase() : '';
  var cod = String(codigo || '').trim();
  var nova = String(novaSenha || '').trim();
  if (!emailNorm) return responderPadrao(false, "Indique su correo.", null);
  if (!cod) return responderPadrao(false, "Indique el código recibido por correo.", null);
  if (!nova) return responderPadrao(false, "Indique la nueva contraseña.", null);

  var sheetReset = getOrCreateResetSheet();
  var dataReset = sheetReset.getDataRange().getValues();
  var colCodigo = 1;
  var colFecha = 2;
  var rowValida = -1;
  var ahora = new Date();
  var limiteMs = RESET_CODE_VALID_MINUTES * 60 * 1000;

  for (var i = 1; i < dataReset.length; i++) {
    if (String(dataReset[i][0] || '').toLowerCase().trim() !== emailNorm) continue;
    if (String(dataReset[i][colCodigo] || '').trim() !== cod) continue;
    var fecha = dataReset[i][colFecha];
    if (fecha && (ahora - new Date(fecha)) > limiteMs) continue;
    rowValida = i + 1;
    break;
  }
  if (rowValida < 0) return responderPadrao(false, "Código incorrecto o expirado. Solicite uno nuevo.", null);

  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheetUsu = ss.getSheetByName("Usuarios") || ss.getSheetByName("Usuários");
  if (!sheetUsu) {
    for (var si = 0; si < ss.getSheets().length; si++) {
      if (ss.getSheets()[si].getName().toLowerCase().indexOf("usuario") >= 0) {
        sheetUsu = ss.getSheets()[si];
        break;
      }
    }
  }
  if (!sheetUsu) return responderPadrao(false, "Hoja Usuarios no encontrada.", null);

  var data = sheetUsu.getDataRange().getValues();
  var header = data[0];
  var colEmail = -1;
  var colSenha = -1;
  for (var h = 0; h < header.length; h++) {
    var n = String(header[h] || '').trim().toLowerCase();
    if (colEmail < 0 && (n === 'email' || n === 'correo' || n.indexOf('email') >= 0)) colEmail = h;
    if (colSenha < 0 && (n === 'senha' || n === 'password' || n === 'contraseña' || n.indexOf('senha') >= 0 || n.indexOf('password') >= 0)) colSenha = h;
  }
  if (colEmail < 0 || colSenha < 0) return responderPadrao(false, "Columnas de correo o contraseña no encontradas.", null);

  for (var i = 1; i < data.length; i++) {
    if (String(data[i][colEmail] || '').toLowerCase().trim() !== emailNorm) continue;
    sheetUsu.getRange(i + 1, colSenha + 1).setValue(nova);
    sheetReset.getRange(rowValida, 1, rowValida, 3).clearContent();
    return responderPadrao(true, "Contraseña restablecida correctamente. Ya puede iniciar sesión.", null);
  }
  return responderPadrao(false, "Usuario no encontrado.", null);
}

// Diagnóstico: retorna informações para identificar o problema
function loginDebug(emailBuscado) {
  var result = { debug: true, sheetFound: false, headers: [], colEmail: -1, colSenha: -1, totalRows: 0, emailsNaPlanilha: [], emailBuscado: (emailBuscado || '').toString().trim() };
  
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheets = ss.getSheets();
    var sheetNames = sheets.map(function(s) { return s.getName(); });
    
    var sheet = ss.getSheetByName("Usuarios") || ss.getSheetByName("Usuários") || ss.getSheetByName("Usuarios");
    if (!sheet) {
      for (var si = 0; si < sheets.length; si++) {
        if (sheets[si].getName().toLowerCase().indexOf('usuario') >= 0) {
          sheet = sheets[si];
          break;
        }
      }
    }
    
    if (!sheet) {
      result.erro = "Nenhuma aba com 'Usuario' encontrada. Abas existentes: " + sheetNames.join(", ");
      return responderJSON(result);
    }
    
    result.sheetFound = true;
    result.sheetName = sheet.getName();
    var data = sheet.getDataRange().getValues();
    var header = data[0];
    result.headers = header;
    result.totalRows = data.length - 1;
    
    var colEmail = -1, colSenha = -1;
    for (var h = 0; h < header.length; h++) {
      var nomeCol = String(header[h] || '').trim().toLowerCase();
      if (colEmail === -1 && (nomeCol.indexOf('email') >= 0 || nomeCol.indexOf('correo') >= 0 || nomeCol === 'e-mail')) colEmail = h;
      if (colSenha === -1 && (nomeCol.indexOf('senha') >= 0 || nomeCol.indexOf('password') >= 0 || nomeCol.indexOf('contraseña') >= 0)) colSenha = h;
    }
    
    result.colEmail = colEmail;
    result.colSenha = colSenha;
    result.headerEmail = colEmail >= 0 ? header[colEmail] : null;
    result.headerSenha = colSenha >= 0 ? header[colSenha] : null;
    
    if (colEmail >= 0) {
      var emails = [];
      for (var i = 1; i < Math.min(data.length, 6); i++) {
        var val = data[i][colEmail];
        emails.push({ row: i + 1, raw: val, str: String(val || '') });
      }
      result.emailsNaPlanilha = emails;
    }
    
  } catch (err) {
    result.erro = err.toString();
  }
  
  return responderJSON(result);
}

// --- 3. INTELIGÊNCIA DE NEGÓCIO 

function normalizarTexto(t) {
  if (!t) return "";
  return String(t).normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLowerCase();
}

function estaAutorizado(nome, colunaIndex) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var abaUsuarios = ss.getSheetByName("Usuarios");
  var dados = abaUsuarios.getDataRange().getValues();
  if (!nome) return false;

  var nomeBusca = normalizarTexto(nome);

  for (var i = 1; i < dados.length; i++) {
    if (dados[i][1]) {
      if (normalizarTexto(dados[i][1]) === nomeBusca) {
        var valor = dados[i][colunaIndex];
        return valor === true || String(valor).toUpperCase() === "TRUE";
      }
    }
  }
  return false;
}

function processarPrioridadesOrdenacao() {
  var r = getDemandasSheet();
  if (!r.data.length) return;
  var m = r.headerMap;
  var colResp = getCol(m, ['responsable']);
  var colStatus = getCol(m, ['status']);
  var colData = getCol(m, ['fecha_necesaria']);
  var colHora = getCol(m, ['hora']);
  var colTema = getCol(m, ['tema']);
  var colReq = getCol(m, ['requerimiento']);
  var colPrioridad = getCol(m, ['prioridad']);
  if (colResp < 0 || colPrioridad < 0) colPrioridad = 10;
  if (colData < 0) colData = 11;
  if (colHora < 0) colHora = 12;
  if (colStatus < 0) colStatus = 16;
  if (colTema < 0) colTema = 1;
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(SHEET_DEMANDAS);
  var data = r.data;
  var tarefasPorResp = {};
  for (var i = 0; i < data.length; i++) {
    var responsavel = String(data[i][colResp] || '').trim();
    var status = String(data[i][colStatus] || '').toLowerCase();
    if (status === 'resuelto') continue;
    if (!responsavel || responsavel === 'undefined') continue;
    var dataVal = data[i][colData];
    var horaVal = data[i][colHora];
    var dataObj = (dataVal instanceof Date) ? dataVal : new Date(dataVal);
    var timeWeight = (dataObj && !isNaN(dataObj.getTime())) ? dataObj.getTime() : 0;
    if (!tarefasPorResp[responsavel]) tarefasPorResp[responsavel] = [];
    tarefasPorResp[responsavel].push({
      sheetRow: DATA_START_ROW + i,
      index: i,
      tema: data[i][colTema],
      requerimiento: colReq >= 0 ? data[i][colReq] : '',
      timestamp: timeWeight
    });
  }
  for (var resp in tarefasPorResp) {
    var lista = tarefasPorResp[resp];
    lista.sort(function(a, b) { return a.timestamp - b.timestamp; });
    lista.forEach(function(tarefa, index) {
      var rank = index + 1;
      sheet.getRange(tarefa.sheetRow, colPrioridad >= 0 ? colPrioridad + 1 : 11).setValue(rank);
    });
  }
}

// --- 4. API DE DEMANDAS (Respuestas del Form) ---

function getDemandasSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(SHEET_DEMANDAS);
  if (!sheet) return { data: [], header: [], headerMap: {} };
  var lastRow = sheet.getLastRow();
  var lastCol = Math.max(sheet.getLastColumn(), 1);
  if (lastRow < HEADER_ROW || lastCol < 1) return { data: [], header: [], headerMap: {} };
  var header = sheet.getRange(HEADER_ROW, 1, HEADER_ROW, lastCol).getValues()[0];
  var headerMap = buildHeaderMap(header);
  var data = [];
  if (lastRow >= DATA_START_ROW) {
    data = sheet.getRange(DATA_START_ROW, 1, lastRow, lastCol).getValues();
  }
  return { data: data, header: header, headerMap: headerMap };
}

/** Diagnóstico: retorna headers, mapeamento e amostra de dados para verificar por que DEMANDAS não mostra itens */
function getDemandasDebug(sector) {
  var r = getDemandasSheet();
  var diag = {
    sheetFound: !!r.header.length,
    headerRow: HEADER_ROW,
    dataStartRow: DATA_START_ROW,
    totalDataRows: r.data ? r.data.length : 0,
    headers: r.header || [],
    headerMap: r.headerMap || {},
    colSector: getCol(r.headerMap, ['sector']),
    colTema: getCol(r.headerMap, ['tema']),
    sectorBuscado: sector || 'Topografía',
    amostraSector: [],
    totalPassariaFiltro: 0,
    erro: null
  };
  if (!r.data || !r.data.length) {
    diag.erro = 'Nenhum dado na planilha ou sheet não encontrada. Verifique: (1) Nome da aba = "Respuestas del Form" (2) HEADER_ROW=6 é a linha dos cabeçalhos? (3) Dados a partir da linha 7?';
    return responderPadrao(true, 'Debug', diag);
  }
  var m = r.headerMap;
  var data = r.data;
  var colSector = getCol(m, ['sector']);
  if (colSector < 0) colSector = getCol(m, ['tema']);
  var colEmail = getCol(m, ['email_solicitante']);
  var colResp = getCol(m, ['responsable']);
  var passam = 0;
  for (var i = 0; i < Math.min(10, data.length); i++) {
    var rowSector = colSector >= 0 ? String(data[i][colSector] || '').toLowerCase() : '';
    var pasa = !sector || rowSector.indexOf((sector || '').toLowerCase()) >= 0;
    if (i < 5) diag.amostraSector.push({ linha: DATA_START_ROW + i, valorSector: rowSector || '(vazio)', pasa: pasa });
    if (pasa) passam++;
  }
  for (var i = 5; i < data.length; i++) {
    var rowSector = colSector >= 0 ? String(data[i][colSector] || '').toLowerCase() : '';
    if (!sector || rowSector.indexOf((sector || '').toLowerCase()) >= 0) passam++;
  }
  diag.totalPassariaFiltro = passam;
  diag.dica = 'O valor na coluna Sector (índice ' + colSector + ') deve conter "' + (sector || 'Topografía') + '". Se HEADER_ROW=6 não for a linha dos títulos, altere no script.';
  return responderPadrao(true, 'Debug', diag);
}

function isPerfilGerencial(perfil) {
  var p = (perfil || '').toString().trim().toLowerCase();
  return p.indexOf('gerente') >= 0 || p.indexOf('coordenador') >= 0 || p.indexOf('coordinador') >= 0 || p.indexOf('manager') >= 0 || p.indexOf('supervisor') >= 0;
}

/** Perfis que podem acessar GESTION: Coordenador, Gerentes, Directores. */
function isPerfilGestion(perfil) {
  var p = (perfil || '').toString().trim().toLowerCase();
  return p.indexOf('coordenador') >= 0 || p.indexOf('coordinador') >= 0 || p.indexOf('gerente') >= 0 || p.indexOf('manager') >= 0 || p.indexOf('director') >= 0;
}

/**
 * Regras: Director/Gerente=todos no setor; Coordinador=todos no setor;
 * Ejecutor=atribuídas a si (responsable); Solicitante=solicitadas por si (email).
 */
function tipoFiltroDemandas(perfil) {
  var p = (perfil || '').toString().trim().toLowerCase();
  if (p.indexOf('director') >= 0 || p.indexOf('gerente') >= 0 || p.indexOf('manager') >= 0) return 'todos';
  if (p.indexOf('coordenador') >= 0 || p.indexOf('coordinador') >= 0) return 'todos';
  if (p.indexOf('ejecutor') >= 0) return 'por_responsable';
  return 'por_solicitante';
}

/** Retorna array de demandas filtrado por sector de destino e perfil (lógica interna reutilizada) */
function _getDemandasArray(sector, email, perfil, responsable) {
  var r = getDemandasSheet();
  if (!r.data.length) return [];
  var m = r.headerMap;
  var data = r.data;
  var colTema = getCol(m, ['tema']);
  var colTipo = getCol(m, ['tipo']);
  var colLocal = getCol(m, ['local']);
  var colSector = getCol(m, ['sector']);
  var colSectorDestino = getCol(m, ['sector_destino']);
  var colSolicitante = getCol(m, ['solicitante']);
  var colEmail = getCol(m, ['email_solicitante']);
  var colReq = getCol(m, ['requerimiento']);
  var colResp = getCol(m, ['responsable']);
  var colData = getCol(m, ['fecha_necesaria']);
  var colHora = getCol(m, ['hora']);
  var colDur = getCol(m, ['duracion']);
  var colStatus = getCol(m, ['status']);
  if (colTema < 0) colTema = 1;
  if (colSector < 0) colSector = colTema;
  if (colEmail < 0) colEmail = colSolicitante;
  if (colSolicitante < 0) colSolicitante = colSector;
  var filtro = tipoFiltroDemandas(perfil);
  var emailNorm = (filtro === 'por_solicitante' && email) ? String(email).trim().toLowerCase() : '';
  var respNorm = (filtro === 'por_responsable' && responsable) ? String(responsable).trim() : '';
  var normalizarTexto = function(s) {
    var t = String(s || '').trim().toLowerCase();
    return t.replace(/á/g,'a').replace(/é/g,'e').replace(/í/g,'i').replace(/ó/g,'o').replace(/ú/g,'u').replace(/ñ/g,'n');
  };
  var out = [];
  for (var i = 0; i < data.length; i++) {
    if (colSectorDestino >= 0 && sector) {
      var rowDestino = String(data[i][colSectorDestino] || '').trim();
      if (normalizarTexto(rowDestino).indexOf(normalizarTexto(sector)) < 0) continue;
    }
    if (filtro === 'por_solicitante' && emailNorm) {
      var solEmail = (colEmail >= 0 ? data[i][colEmail] : data[i][colSolicitante]) || '';
      if (String(solEmail).trim().toLowerCase() !== emailNorm) continue;
    }
    if (filtro === 'por_responsable' && respNorm) {
      var rowResp = (colResp >= 0 ? data[i][colResp] : '') || '';
      if (String(rowResp).trim() !== respNorm) continue;
    }
    var fechaVal = colData >= 0 && data[i][colData] ? data[i][colData] : null;
    var horaVal = colHora >= 0 ? data[i][colHora] : '';
    out.push({
      id: DATA_START_ROW + i,
      index: DATA_START_ROW + i - 1,
      titulo: (data[i][colTema] || '').toString(),
      tipoDemanda: (colTipo >= 0 ? data[i][colTipo] : '').toString(),
      local: (colLocal >= 0 ? data[i][colLocal] : '').toString(),
      solicitanteNome: (colSolicitante >= 0 ? data[i][colSolicitante] : '').toString() || (data[i][colSector] || '').toString(),
      solicitanteEmail: (colEmail >= 0 ? data[i][colEmail] : data[i][colSolicitante] || '').toString().trim() || '',
      setor: (data[i][colSector] || '').toString(),
      status: (colStatus >= 0 ? data[i][colStatus] : 'Pendiente').toString(),
      fechaNecesaria: fechaVal ? Utilities.formatDate(new Date(fechaVal), Session.getScriptTimeZone(), 'dd/MM/yyyy') : '',
      horaInicio: horaVal ? String(horaVal).trim() : '',
      duracion: (colDur >= 0 ? data[i][colDur] : '').toString(),
      prioridad: (colResp >= 0 && data[i][colResp] ? 1 : 0),
      solicitante: (colSolicitante >= 0 ? data[i][colSolicitante] : data[i][colSector] || '').toString(),
      Email_Solicitante: (colEmail >= 0 ? data[i][colEmail] : data[i][colSolicitante] || '').toString().trim() || '',
      sector: (data[i][colSector] || '').toString(),
      data: fechaVal ? Utilities.formatDate(new Date(fechaVal), Session.getScriptTimeZone(), 'dd/MM/yyyy') : '',
      responsavel: (colResp >= 0 ? data[i][colResp] : '').toString(),
      requerimiento: (colReq >= 0 ? data[i][colReq] : '').toString()
    });
  }
  return out;
}

function getDemandas(sector, email, perfil, responsable) {
  var out = _getDemandasArray(sector, email, perfil, responsable);
  return responderPadrao(true, '', { demandas: out });
}

function getDemandasGestion(sector, perfil, email, responsable) {
  var demandasCompletas = _getDemandasArray(sector, email, perfil, responsable);
  var r = getDemandasSheet();
  if (!r.data.length) return responderPadrao(true, '', { demandas: [] });
  var m = r.headerMap;
  var data = r.data;
  var colResp = getCol(m, ['responsable']);
  var colBrigada = getCol(m, ['brigada']);
  var colStatus = getCol(m, ['status']);
  if (colResp < 0) colResp = 9;
  if (colStatus < 0) colStatus = 16;
  if (colBrigada < 0) colBrigada = 15;
  var filtro = tipoFiltroDemandas(perfil);
  var out = [];
  for (var i = 0; i < demandasCompletas.length; i++) {
    var idx = demandasCompletas[i].index;
    if (idx == null || idx === undefined) continue;
    var rowIdx = idx - (DATA_START_ROW - 1);
    if (rowIdx < 0 || rowIdx >= data.length) continue;
    var row = data[rowIdx];
    var st = String(row[colStatus] || '').toLowerCase();
    if (st === 'resuelto' || st.indexOf('cancel') >= 0 || st.indexOf('reprogram') >= 0) continue;
    var brigada = String(row[colBrigada] || '').trim();
    if (brigada !== '' && brigada !== 'undefined') continue;
    var resp = String(row[colResp] || '').trim();
    if (resp !== '' && resp !== 'undefined') continue;
    if (filtro === 'por_responsable') continue;
    out.push(demandasCompletas[i]);
  }
  return responderPadrao(true, '', { demandas: out });
}

function getDemandasAgenda(sector, email, perfil, responsable) {
  var r = getDemandasSheet();
  if (!r.data.length) return responderPadrao(true, '', { demandas: [] });
  var m = r.headerMap;
  var data = r.data;
  var colTema = getCol(m, ['tema']);
  var colTipo = getCol(m, ['tipo']);
  var colLocal = getCol(m, ['local']);
  var colResp = getCol(m, ['responsable']);
  var colSolicitante = getCol(m, ['solicitante']);
  var colEmail = getCol(m, ['email_solicitante']);
  var colData = getCol(m, ['fecha_necesaria']);
  var colHora = getCol(m, ['hora']);
  var colDur = getCol(m, ['duracion']);
  var colStatus = getCol(m, ['status']);
  var colSector = getCol(m, ['sector']);
  var colSectorDestino = getCol(m, ['sector_destino']);
  if (colTema < 0) colTema = 1;
  if (colResp < 0) colResp = 9;
  if (colEmail < 0) colEmail = colSolicitante;
  if (colSolicitante < 0) colSolicitante = colSector;
  if (colData < 0) colData = 11;
  if (colHora < 0) colHora = 12;
  var filtro = tipoFiltroDemandas(perfil);
  var emailNorm = (filtro === 'por_solicitante' && email) ? String(email).trim().toLowerCase() : '';
  var respNorm = (filtro === 'por_responsable' && responsable) ? String(responsable).trim() : '';
  var normalizarTexto = function(s) {
    var t = String(s || '').trim().toLowerCase();
    return t.replace(/á/g,'a').replace(/é/g,'e').replace(/í/g,'i').replace(/ó/g,'o').replace(/ú/g,'u').replace(/ñ/g,'n');
  };
  var out = [];
  for (var i = 0; i < data.length; i++) {
    if (colSectorDestino >= 0 && sector) {
      var rowDestino = String(data[i][colSectorDestino] || '').trim();
      if (normalizarTexto(rowDestino).indexOf(normalizarTexto(sector)) < 0) continue;
    }
    var resp = String(data[i][colResp] || '').trim();
    if (!resp || resp === 'undefined') continue;
    if (filtro === 'por_solicitante' && emailNorm) {
      var solEmail = (colEmail >= 0 ? data[i][colEmail] : data[i][colSolicitante]) || '';
      if (String(solEmail).trim().toLowerCase() !== emailNorm) continue;
    }
    if (filtro === 'por_responsable' && respNorm) {
      if (String(resp) !== respNorm) continue;
    }
    var dur = colDur >= 0 ? data[i][colDur] : (data[i][colHora] ? 1 : null);
    if (!dur) continue;
    var d = data[i][colData];
    if (!d) continue;
    try {
      var dataObj = (d instanceof Date) ? d : new Date(d);
      if (isNaN(dataObj.getTime())) continue;
    } catch (e) { continue; }
    var dataStr = Utilities.formatDate(new Date(d), Session.getScriptTimeZone(), 'dd/MM/yyyy');
    var horaStr = data[i][colHora] ? String(data[i][colHora]).substring(0, 5) : '';
    out.push({
      titulo: (data[i][colTema] || '').toString(),
      tipoDemanda: (colTipo >= 0 ? data[i][colTipo] : '').toString(),
      local: (colLocal >= 0 ? data[i][colLocal] : '').toString(),
      setor: (colSector >= 0 ? data[i][colSector] : '').toString(),
      responsavel: resp,
      data: dataStr,
      hora: horaStr,
      duracion: String(dur),
      index: DATA_START_ROW + i - 1
    });
  }
  out.sort(function(a, b) {
    var da = (a.data || '') + (a.hora || '');
    var db = (b.data || '') + (b.hora || '');
    return da.localeCompare(db);
  });
  return responderPadrao(true, '', { demandas: out });
}

function getKPIs(sector) {
  var r = getDemandasSheet();
  var total = 0, pendentes = 0, resolvidas = 0;
  if (r.data.length > 0) {
    var m = r.headerMap;
    var data = r.data;
    var colResp = getCol(m, ['responsable']);
    var colStatus = getCol(m, ['status']);
    var colSectorDestino = getCol(m, ['sector_destino']);
    var normalizarTexto = function(s) {
      var t = String(s || '').trim().toLowerCase();
      return t.replace(/á/g,'a').replace(/é/g,'e').replace(/í/g,'i').replace(/ó/g,'o').replace(/ú/g,'u').replace(/ñ/g,'n');
    };
    if (colResp < 0) colResp = 9;
    if (colStatus < 0) colStatus = 16;
    for (var i = 0; i < data.length; i++) {
      if (colSectorDestino >= 0 && sector) {
        var rowDestino = String(data[i][colSectorDestino] || '').trim();
        if (normalizarTexto(rowDestino).indexOf(normalizarTexto(sector)) < 0) continue;
      }
      total++;
      var st = String(data[i][colStatus] || '').toLowerCase();
      if (st === 'resuelto') resolvidas++;
      else if (String(data[i][colResp] || '').trim() === '') pendentes++;
    }
  }
  return responderPadrao(true, '', { total: total, pendentesProgramacao: pendentes, resolvidas: resolvidas });
}

// --- 5. SALVAR DEMANDA (com trava 4 brigadas e status forçado) ---

function getOcupacaoParaSlot(dataStr, horaStr, sector) {
  var r = getDemandasSheet();
  if (!r.data.length || !dataStr) return 0;
  var m = r.headerMap;
  var colData = getCol(m, ['fecha_necesaria']);
  var colHora = getCol(m, ['hora']);
  var colSectorDestino = getCol(m, ['sector_destino']);
  var colStatus = getCol(m, ['status']);
  var normalizarTexto = function(s) {
    var t = String(s || '').trim().toLowerCase();
    return t.replace(/á/g,'a').replace(/é/g,'e').replace(/í/g,'i').replace(/ó/g,'o').replace(/ú/g,'u').replace(/ñ/g,'n');
  };
  if (colData < 0) colData = 11;
  if (colHora < 0) colHora = 12;
  if (colStatus < 0) colStatus = 16;
  var horaKey = horaStr ? String(horaStr).trim() : '';
  if (horaKey.length >= 5) horaKey = horaKey.substring(0, 5);
  else if (horaKey.length === 4 && horaKey.indexOf(':') === 1) horaKey = '0' + horaKey;
  var count = 0;
  for (var i = 0; i < r.data.length; i++) {
    if (colSectorDestino >= 0 && sector) {
      var rowDestino = String(r.data[i][colSectorDestino] || '').trim();
      if (normalizarTexto(rowDestino).indexOf(normalizarTexto(sector)) < 0) continue;
    }
    var st = String(r.data[i][colStatus] || '').toLowerCase();
    if (st === 'cancelada' || st === 'reprogramada') continue;
    var d = r.data[i][colData];
    if (!d) continue;
    var rowDataStr = Utilities.formatDate(new Date(d), Session.getScriptTimeZone(), 'dd/MM/yyyy');
    var rowHoraStr = r.data[i][colHora] ? String(r.data[i][colHora]).trim() : '';
    if (rowHoraStr.length >= 5) rowHoraStr = rowHoraStr.substring(0, 5);
    else if (rowHoraStr.length === 4 && rowHoraStr.indexOf(':') === 1) rowHoraStr = '0' + rowHoraStr;
    if (rowDataStr === dataStr && rowHoraStr === horaKey) count++;
  }
  return count;
}

function salvarDemanda(dados) {
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName(SHEET_DEMANDAS);
    if (!sheet) return responderPadrao(false, "Hoja no encontrada", null);

    var lastCol = Math.max(sheet.getLastColumn(), 1);
    var headers = sheet.getRange(HEADER_ROW, 1, HEADER_ROW, lastCol).getValues()[0];

    var horaVal = (dados.hora || dados.hora_inicio || '').toString().trim();
    var dataStr = '';
    try {
      var fn = String(dados.fecha_necesaria || dados.fechaNecesaria || '');
      if (fn) {
        var parts = fn.split('/');
        if (parts.length === 3) {
          var d = new Date(parseInt(parts[2], 10), parseInt(parts[1], 10) - 1, parseInt(parts[0], 10));
          if (!isNaN(d.getTime())) dataStr = Utilities.formatDate(d, Session.getScriptTimeZone(), 'dd/MM/yyyy');
        }
      }
    } catch (_) {}
    var horaStr = horaVal;
    if (horaStr.length >= 5) horaStr = horaStr.substring(0, 5);
    else if (horaStr.length === 4 && horaStr.indexOf(':') > 0) horaStr = '0' + horaStr;
    var sector = (dados.sectorSolicitante || dados.sector || '').toString().trim();
    if (!dataStr || !horaStr) {
      return responderPadrao(false, "Fecha y hora son obligatorios para validar disponibilidad.", null);
    }
    var ocupacao = getOcupacaoParaSlot(dataStr, horaStr, sector);
    if (ocupacao >= 4) {
      return responderPadrao(false, "Límite de 4 brigadas alcanzado para este horario.", null);
    }

    var row = [];
    for (var i = 0; i < headers.length; i++) {
      var header = String(headers[i] || '').toLowerCase().trim();

      if (i === 0 || header.indexOf('carimbo') >= 0) {
        row.push(new Date());
        continue;
      }

      if (header === 'hora necessaria' || header === 'hora necesaria') {
        row.push(horaVal);
        continue;
      }

      var val = '';
      for (var key in COL_ALIASES) {
        if (!COL_ALIASES.hasOwnProperty(key)) continue;
        if (COL_ALIASES[key].indexOf(header) >= 0) {
          val = getDadosVal(key, dados);
          if (key === 'fecha_necesaria' && val && typeof val === 'string') {
            try {
              var p = String(val).split('/');
              if (p.length === 3) val = new Date(parseInt(p[2], 10), parseInt(p[1], 10) - 1, parseInt(p[0], 10));
            } catch (_) {}
          }
          break;
        }
      }
      row.push(val);
    }

    sheet.appendRow(row);
    return responderPadrao(true, "Demanda gravada con éxito", null);
  } catch (err) {
    return responderPadrao(false, err.toString(), null);
  }
}

function reprogramarDemanda(dados) {
  try {
    var idAnt = dados.idDemandaAnterior || '';
    marcarDemandaComoReprogramada(idAnt);
    var obs = 'Referente à demanda ID: ' + idAnt;
    dados.requerimiento = (dados.requerimiento || '') + (dados.requerimiento ? ' ' : '') + obs;
    return salvarDemanda(dados);
  } catch (err) {
    return responderPadrao(false, err.toString(), null);
  }
}

function marcarDemandaComoReprogramada(idStr) {
  try {
    var idNum = parseInt(idStr, 10);
    if (isNaN(idNum) || idNum < DATA_START_ROW) return;
    var r = getDemandasSheet();
    var m = r.headerMap;
    var colStatus = getCol(m, ['status']);
    if (colStatus < 0) colStatus = 16;
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_DEMANDAS);
    if (!sheet) return;
    sheet.getRange(idNum, colStatus + 1).setValue('Reprogramada');
  } catch (e) { /* log silencioso */ }
}

// --- 6. LOCAIS, REPROGRAMAÇÃO, DISPONIBILIDADE ---

function getLocais() {
  var r = getDemandasSheet();
  if (!r.data.length) return responderPadrao(true, '', { locais: [] });
  var header = r.header;
  var colLocal = getCol(r.headerMap, ['local']);
  var seen = {};
  var locais = [];
  if (colLocal >= 0) {
    for (var i = 0; i < r.data.length; i++) {
      var v = String(r.data[i][colLocal] || '').trim();
      if (v && !seen[v]) { seen[v] = true; locais.push(v); }
    }
  }
  if (locais.length === 0) locais = ['Ponte Jarabacoa', 'Jaguey', 'Retorno San Francisco', 'Marginal San Francisco', 'Outro'];
  return responderPadrao(true, '', { locais: locais });
}

function crearDemandaReprogramada(dados) {
  return reprogramarDemanda(dados);
}

function crearDemandaCancelada(dados) {
  try {
    dados.status = 'Cancelada';
    return salvarDemanda(dados);
  } catch (err) {
    return responderPadrao(false, err.toString(), null);
  }
}

function verificarDisponibilidad(dataHora) {
  var r = getDemandasSheet();
  var limite = 4, count = 0;
  if (r.data.length > 0) {
    var m = r.headerMap;
    var colData = getCol(m, ['fecha_necesaria']);
    var colHora = getCol(m, ['hora']);
    var colStatus = getCol(m, ['status']);
    if (colData < 0) colData = 11;
    if (colHora < 0) colHora = 12;
    if (colStatus < 0) colStatus = 16;
    var target = dataHora ? new Date(dataHora) : new Date();
    var targetDataStr = Utilities.formatDate(target, Session.getScriptTimeZone(), 'dd/MM/yyyy');
    var targetHoraStr = Utilities.formatDate(target, Session.getScriptTimeZone(), 'HH:mm');
    for (var i = 0; i < r.data.length; i++) {
      var st = String(r.data[i][colStatus] || '').toLowerCase();
      if (st === 'cancelada') continue;
      var d = r.data[i][colData];
      if (!d) continue;
      var rowDataStr = Utilities.formatDate(new Date(d), Session.getScriptTimeZone(), 'dd/MM/yyyy');
      var rowHoraStr = r.data[i][colHora] ? String(r.data[i][colHora]).substring(0, 5) : '';
      if (rowDataStr === targetDataStr && rowHoraStr === targetHoraStr) count++;
    }
  }
  return responderPadrao(true, '', { disponible: count < limite, ocupaciones: count, limite: limite });
}

function getOcupacaoBrigadas(sector) {
  var r = getDemandasSheet();
  var ocupacoes = {};
  if (r.data.length > 0) {
    var m = r.headerMap;
    var colData = getCol(m, ['fecha_necesaria']);
    var colHora = getCol(m, ['hora']);
    var colSectorDestino = getCol(m, ['sector_destino']);
    var colStatus = getCol(m, ['status']);
    var normalizarTexto = function(s) {
      var t = String(s || '').trim().toLowerCase();
      return t.replace(/á/g,'a').replace(/é/g,'e').replace(/í/g,'i').replace(/ó/g,'o').replace(/ú/g,'u').replace(/ñ/g,'n');
    };
    if (colData < 0) colData = 11;
    if (colHora < 0) colHora = 12;
    if (colStatus < 0) colStatus = 16;
    for (var i = 0; i < r.data.length; i++) {
      if (colSectorDestino >= 0 && sector) {
        var rowDestino = String(r.data[i][colSectorDestino] || '').trim();
        if (normalizarTexto(rowDestino).indexOf(normalizarTexto(sector)) < 0) continue;
      }
      var st = String(r.data[i][colStatus] || '').toLowerCase();
      if (st === 'cancelada') continue;
      var d = r.data[i][colData];
      if (!d) continue;
      var dataStr = d ? Utilities.formatDate(new Date(d), Session.getScriptTimeZone(), 'dd/MM/yyyy') : '';
      var horaStr = r.data[i][colHora] ? String(r.data[i][colHora]).substring(0, 5) : '';
      var key = dataStr + '|' + horaStr;
      ocupacoes[key] = (ocupacoes[key] || 0) + 1;
    }
  }
  return responderPadrao(true, '', { ocupacoes: ocupacoes });
}

// --- 7. FUNÇÕES DE SUPORTE ---

function responderJSON(objeto) {
  return ContentService.createTextOutput(JSON.stringify(objeto))
    .setMimeType(ContentService.MimeType.JSON);
}

function responderPadrao(success, message, data) {
  var out = { success: !!success, message: (message || '').toString(), data: data };
  return responderJSON(out);
}
