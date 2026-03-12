/**
 * GESTÃO DUARTE - API UNIFICADA (FLUTTER + GOOGLE SHEETS)
 * Versão: 1.2 - Mapeamento robusto, contrato JSON, login POST
 */

// --- CONSTANTES ABA "Respuestas del Form" ---
var HEADER_ROW = 6;
var DATA_START_ROW = HEADER_ROW + 1;

// --- ALIASES DE COLUNAS (compatíveis com "Respuestas del Form") ---
// Colunas exatas: Carimbo de data/hora | Tipo de Demanda | Sector de Destino | Secctor Solicitante | Solicitante | Requerimiento | Local | Coordenadas | Estatus Técnico | Responsable | Prioridad | Fecha Necesaria | Hora Necessaria | Duracion Estimada | Hora Fin | Brigada Topografica | Estatus Actual
var COL_ALIASES = {
  tema: ['requerimiento', 'tema', 'título', 'titulo', 'tipo de demanda'],
  sector: ['secctor solicitante', 'sector solicitante', 'sector', 'setor', 'setor solicitante'],
  sector_destino: ['sector de destino', 'sector destino', 'destino', 'setor destino'],
  solicitante: ['solicitante', 'nombre', 'nome solicitante'],
  email_solicitante: ['email_solicitante', 'email solicitante', 'correo solicitante', 'e-mail solicitante'],
  requerimiento: ['requerimiento', 'requisito', 'descripcion'],
  responsable: ['responsable', 'responsavel', 'responsable asignado'],
  fecha_necesaria: ['fecha necesaria', 'fecha necessaria', 'fecha', 'date'],
  hora: ['hora necessaria', 'hora necesaria', 'hora inicio', 'hora', 'time'],
  duracion: ['duracion estimada', 'duración', 'duracion'],
  status: ['estatus actual', 'status', 'estado', 'estatus'],
  brigada: ['brigada topografica', 'brigada', 'equipe'],
  local: ['local', 'ubicación', 'ubicacion'],
  prioridad: ['prioridad', 'prioridade', 'rank', 'orden'],
  tipo: ['tipo de demanda', 'tipo', 'tipo demanda'],
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

// --- 1. PORTA DE ENTRADA (Comunicação com Flutter) ---

function doGet(e) {
  var action = (e && e.parameter) ? e.parameter.action : null;
  try {
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

// --- 3. SUA INTELIGÊNCIA DE NEGÓCIO (Original adaptada) ---

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
  var sheet = ss.getSheetByName("Respuestas del Form");
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
  var sheet = ss.getSheetByName("Respuestas del Form");
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

function getDemandas(sector, email, perfil, responsable) {
  var r = getDemandasSheet();
  if (!r.data.length) return responderPadrao(true, '', { demandas: [] });
  var m = r.headerMap;
  var data = r.data;
  var colTema = getCol(m, ['tema']);
  var colTipo = getCol(m, ['tipo']);
  var colLocal = getCol(m, ['local']);
  var colSector = getCol(m, ['sector']);
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
  var out = [];
  for (var i = 0; i < data.length; i++) {
    var rowSector = colSector >= 0 ? String(data[i][colSector] || '').toLowerCase() : '';
    if (sector && rowSector.indexOf(sector.toLowerCase()) < 0) continue;
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
  return responderPadrao(true, '', { demandas: out });
}

function getDemandasGestion(sector, perfil, email, responsable) {
  var r = getDemandasSheet();
  if (!r.data.length) return responderPadrao(true, '', { demandas: [] });
  var m = r.headerMap;
  var data = r.data;
  var colTema = getCol(m, ['tema']);
  var colResp = getCol(m, ['responsable']);
  var colSolicitante = getCol(m, ['solicitante']);
  var colEmail = getCol(m, ['email_solicitante']);
  var colStatus = getCol(m, ['status']);
  var colSector = getCol(m, ['sector']);
  var colBrigada = getCol(m, ['brigada']);
  if (colTema < 0) colTema = 1;
  if (colResp < 0) colResp = 9;
  if (colEmail < 0) colEmail = colSolicitante;
  if (colSolicitante < 0) colSolicitante = colSector;
  if (colStatus < 0) colStatus = 16;
  if (colBrigada < 0) colBrigada = 15;
  var filtro = tipoFiltroDemandas(perfil);
  var emailNorm = (filtro === 'por_solicitante' && email) ? String(email).trim().toLowerCase() : '';
  var out = [];
  for (var i = 0; i < data.length; i++) {
    var st = String(data[i][colStatus] || '').toLowerCase();
    if (st === 'resuelto' || st.indexOf('cancel') >= 0 || st.indexOf('reprogram') >= 0) continue;
    var brigada = String(data[i][colBrigada] || '').trim();
    if (brigada !== '' && brigada !== 'undefined') continue;
    var resp = String(data[i][colResp] || '').trim();
    if (resp !== '' && resp !== 'undefined') continue;
    if (colSector >= 0 && sector && String(data[i][colSector] || '').toLowerCase().indexOf(sector.toLowerCase()) < 0) continue;
    if (filtro === 'por_solicitante' && emailNorm) {
      var solEmail = (colEmail >= 0 ? data[i][colEmail] : data[i][colSolicitante]) || '';
      if (String(solEmail).trim().toLowerCase() !== emailNorm) continue;
    }
    if (filtro === 'por_responsable') continue;
    out.push({ id: DATA_START_ROW + i, tema: (data[i][colTema] || '').toString(), index: DATA_START_ROW + i - 1 });
  }
  return responderPadrao(true, '', { demandas: out });
}

function getDemandasAgenda(sector, email, perfil, responsable) {
  var r = getDemandasSheet();
  if (!r.data.length) return responderPadrao(true, '', { demandas: [] });
  var m = r.headerMap;
  var data = r.data;
  var colTema = getCol(m, ['tema']);
  var colResp = getCol(m, ['responsable']);
  var colSolicitante = getCol(m, ['solicitante']);
  var colEmail = getCol(m, ['email_solicitante']);
  var colData = getCol(m, ['fecha_necesaria']);
  var colHora = getCol(m, ['hora']);
  var colDur = getCol(m, ['duracion']);
  var colStatus = getCol(m, ['status']);
  var colSector = getCol(m, ['sector']);
  if (colTema < 0) colTema = 1;
  if (colResp < 0) colResp = 9;
  if (colEmail < 0) colEmail = colSolicitante;
  if (colSolicitante < 0) colSolicitante = colSector;
  if (colData < 0) colData = 11;
  if (colHora < 0) colHora = 12;
  var filtro = tipoFiltroDemandas(perfil);
  var emailNorm = (filtro === 'por_solicitante' && email) ? String(email).trim().toLowerCase() : '';
  var respNorm = (filtro === 'por_responsable' && responsable) ? String(responsable).trim() : '';
  var out = [];
  for (var i = 0; i < data.length; i++) {
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
    if (colSector >= 0 && sector && String(data[i][colSector] || '').toLowerCase().indexOf(sector.toLowerCase()) < 0) continue;
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
    var colSector = getCol(m, ['sector']);
    if (colResp < 0) colResp = 9;
    if (colStatus < 0) colStatus = 16;
    for (var i = 0; i < data.length; i++) {
      if (colSector >= 0 && sector && String(data[i][colSector] || '').toLowerCase().indexOf(sector.toLowerCase()) < 0) continue;
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
  var colSector = getCol(m, ['sector']);
  var colStatus = getCol(m, ['status']);
  if (colData < 0) colData = 11;
  if (colHora < 0) colHora = 12;
  if (colStatus < 0) colStatus = 16;
  var horaKey = horaStr ? String(horaStr).trim() : '';
  if (horaKey.length >= 5) horaKey = horaKey.substring(0, 5);
  else if (horaKey.length === 4 && horaKey.indexOf(':') === 1) horaKey = '0' + horaKey;
  var count = 0;
  for (var i = 0; i < r.data.length; i++) {
    if (colSector >= 0 && sector && String(r.data[i][colSector] || '').toLowerCase().indexOf(sector.toLowerCase()) < 0) continue;
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
    var r = getDemandasSheet();
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName("Respuestas del Form");
    if (!sheet) return responderPadrao(false, "Hoja no encontrada", null);
    var header = r.header;
    var m = r.headerMap;
    var row = [];
    for (var c = 0; c < header.length; c++) row.push('');
    // Coluna 0: Carimbo de data/hora do envio (vem do dispositivo)
    if (dados.carimbo && String(dados.carimbo).trim()) {
      try {
        var s = String(dados.carimbo).trim();
        var partes = s.split(' ');
        var dataPart = partes[0] ? partes[0].split('/') : [];
        var horaPart = (partes[1] || '00:00:00').split(':');
        if (dataPart.length >= 3) {
          var ano = parseInt(dataPart[2], 10);
          var mes = parseInt(dataPart[1], 10) - 1;
          var dia = parseInt(dataPart[0], 10);
          var h = parseInt(horaPart[0] || '0', 10);
          var min = parseInt(horaPart[1] || '0', 10);
          var seg = parseInt(horaPart[2] || '0', 10);
          row[0] = new Date(ano, mes, dia, h, min, seg);
        } else {
          row[0] = new Date();
        }
      } catch (_) {
        row[0] = new Date();
      }
    } else {
      row[0] = new Date();
    }
    var colTema = getCol(m, ['tema']);
    if (colTema >= 0) row[colTema] = dados.tema || dados.tipoDemanda || dados.requerimiento || 'Nueva demanda';
    var colSec = getCol(m, ['sector']);
    if (colSec >= 0) row[colSec] = dados.sectorSolicitante || dados.sector || '';
    var colSol = getCol(m, ['solicitante']);
    if (colSol >= 0) row[colSol] = dados.solicitante || '';
    var colDest = getCol(m, ['sector_destino']);
    if (colDest >= 0) row[colDest] = dados.sectorDestino || '';
    var colTipo = getCol(m, ['tipo']);
    if (colTipo >= 0) row[colTipo] = dados.tipoDemanda || '';
    var colLocal = getCol(m, ['local']);
    if (colLocal >= 0) row[colLocal] = dados.local || '';
    var colReq = getCol(m, ['requerimiento']);
    if (colReq >= 0) row[colReq] = dados.requerimiento || '';
    var colFecha = getCol(m, ['fecha_necesaria']);
    if (colFecha >= 0 && dados.fechaNecesaria) {
      try {
        var parts = String(dados.fechaNecesaria).split('/');
        if (parts.length === 3) row[colFecha] = new Date(parseInt(parts[2]), parseInt(parts[1]) - 1, parseInt(parts[0]));
        else row[colFecha] = dados.fechaNecesaria;
      } catch (_) { row[colFecha] = dados.fechaNecesaria; }
    }
    var colHora = getCol(m, ['hora']);
    // Se colHora === 0, é Carimbo; buscar coluna "Hora Necessaria" explicitamente
    if (colHora === 0) {
      colHora = -1;
      for (var hi = 0; hi < header.length; hi++) {
        var hn = String(header[hi] || '').trim().toLowerCase();
        if (hn.indexOf('carimbo') >= 0) continue;
        if ((hn.indexOf('hora necessaria') >= 0 || hn.indexOf('hora necesaria') >= 0 || hn.indexOf('hora inicio') >= 0)) {
          colHora = hi;
          break;
        }
      }
    }
    if (colHora >= 0) row[colHora] = dados.horaInicio || '';
    var colResp = getCol(m, ['responsable']);
    if (colResp >= 0) row[colResp] = dados.responsable || '';
    var colDur = getCol(m, ['duracion']);
    if (colDur >= 0) row[colDur] = dados.duracion || '';
    var colRef = getCol(m, ['id_anterior']);
    if (colRef >= 0 && dados.idDemandaAnterior) row[colRef] = dados.idDemandaAnterior;
    var colCoord = getCol(m, ['coordenada']);
    if (colCoord >= 0 && dados.coordenadas) row[colCoord] = dados.coordenadas;
    var colStatus = getCol(m, ['status']);
    var statusFinal = (dados.status && String(dados.status).trim() !== '') ? String(dados.status).trim() : 'No Programada';
    if (colStatus >= 0) row[colStatus] = statusFinal;
    var colHoraFin = getCol(m, ['hora_fin']);
    if (colHoraFin >= 0 && dados.horaFin) row[colHoraFin] = dados.horaFin;
    var dataStr = '';
    var horaStr = (dados.horaInicio || '').toString().trim();
    if (horaStr.length >= 5) horaStr = horaStr.substring(0, 5);
    else if (horaStr.length === 4 && horaStr.indexOf(':') > 0) horaStr = '0' + horaStr;
    try {
      if (dados.fechaNecesaria) {
        var parts = String(dados.fechaNecesaria).split('/');
        if (parts.length === 3) {
          var d = new Date(parseInt(parts[2], 10), parseInt(parts[1], 10) - 1, parseInt(parts[0], 10));
          if (!isNaN(d.getTime())) dataStr = Utilities.formatDate(d, Session.getScriptTimeZone(), 'dd/MM/yyyy');
        }
      }
    } catch (_) {}
    var sector = (dados.sectorSolicitante || dados.sector || '').toString().trim();
    if (!dataStr || !horaStr) {
      return responderPadrao(false, "Fecha y hora son obligatorios para validar disponibilidad.", null);
    }
    var ocupacao = getOcupacaoParaSlot(dataStr, horaStr, sector);
    if (ocupacao >= 4) {
      return responderPadrao(false, "Límite de 4 brigadas alcanzado para este horario.", null);
    }
    sheet.appendRow(row);
    return responderPadrao(true, "Demanda creada", null);
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
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("Respuestas del Form");
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
    var colSector = getCol(m, ['sector']);
    var colStatus = getCol(m, ['status']);
    if (colData < 0) colData = 11;
    if (colHora < 0) colHora = 12;
    if (colStatus < 0) colStatus = 16;
    for (var i = 0; i < r.data.length; i++) {
      if (colSector >= 0 && sector && String(r.data[i][colSector] || '').toLowerCase().indexOf(sector.toLowerCase()) < 0) continue;
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
