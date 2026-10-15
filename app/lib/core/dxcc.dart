// Tabela compacta prefixo -> país/continente para identificar a estação (aproximação por prefixo).
// Não substitui o cty.dat completo (ARRL DXCC); cobre as entidades mais comuns e, como reserva,
// os blocos de alocação da UIT.

class DxccInfo {
  const DxccInfo(this.country, this.continent);
  final String country;
  final String continent;
}

// "prefixo=País|Continente". Os prefixos mais longos têm prioridade.
const String _raw = '''
PP=Brasil|SA;PQ=Brasil|SA;PR=Brasil|SA;PS=Brasil|SA;PT=Brasil|SA;PU=Brasil|SA;PV=Brasil|SA;PW=Brasil|SA;PX=Brasil|SA;PY=Brasil|SA;ZV=Brasil|SA;ZW=Brasil|SA;ZX=Brasil|SA;ZY=Brasil|SA;ZZ=Brasil|SA;
PY0F=Fernando de Noronha|SA;PY0S=São Pedro e São Paulo|SA;PY0T=Trindade e Martim Vaz|SA;
LU=Argentina|SA;LO=Argentina|SA;LP=Argentina|SA;LQ=Argentina|SA;LR=Argentina|SA;LS=Argentina|SA;LT=Argentina|SA;LV=Argentina|SA;LW=Argentina|SA;AY=Argentina|SA;AZ=Argentina|SA;L2=Argentina|SA;L3=Argentina|SA;L4=Argentina|SA;L5=Argentina|SA;L6=Argentina|SA;L7=Argentina|SA;L8=Argentina|SA;L9=Argentina|SA;
CX=Uruguai|SA;CV=Uruguai|SA;CW=Uruguai|SA;ZP=Paraguai|SA;CE=Chile|SA;CA=Chile|SA;CB=Chile|SA;CC=Chile|SA;CD=Chile|SA;XQ=Chile|SA;XR=Chile|SA;3G=Chile|SA;
CP=Bolívia|SA;OA=Peru|SA;OB=Peru|SA;OC=Peru|SA;HC=Equador|SA;HD=Equador|SA;HK=Colômbia|SA;HJ=Colômbia|SA;5J=Colômbia|SA;5K=Colômbia|SA;YV=Venezuela|SA;YW=Venezuela|SA;YX=Venezuela|SA;YY=Venezuela|SA;4M=Venezuela|SA;
8R=Guiana|SA;PZ=Suriname|SA;FY=Guiana Francesa|SA;
K=EUA|NA;N=EUA|NA;W=EUA|NA;AA=EUA|NA;AB=EUA|NA;AC=EUA|NA;AD=EUA|NA;AE=EUA|NA;AF=EUA|NA;AG=EUA|NA;AI=EUA|NA;AJ=EUA|NA;AK=EUA|NA;KH6=Havaí|OC;KL=Alasca|NA;AL=Alasca|NA;NL=Alasca|NA;WL=Alasca|NA;KP4=Porto Rico|NA;NP4=Porto Rico|NA;WP4=Porto Rico|NA;KP2=Ilhas Virgens (EUA)|NA;KG4=Guantánamo|NA;KH2=Guam|OC;
VE=Canadá|NA;VA=Canadá|NA;VO=Canadá|NA;VY=Canadá|NA;CF=Canadá|NA;CG=Canadá|NA;CH=Canadá|NA;CI=Canadá|NA;CJ=Canadá|NA;CK=Canadá|NA;
XE=México|NA;XA=México|NA;XB=México|NA;XC=México|NA;XD=México|NA;XF=México|NA;4A=México|NA;4B=México|NA;4C=México|NA;6D=México|NA;6E=México|NA;6F=México|NA;6G=México|NA;6H=México|NA;6I=México|NA;6J=México|NA;
CO=Cuba|NA;CM=Cuba|NA;T4=Cuba|NA;HI=Rep. Dominicana|NA;HH=Haiti|NA;6Y=Jamaica|NA;J3=Granada|NA;J6=Santa Lúcia|NA;J7=Dominica|NA;J8=São Vicente|NA;V2=Antígua e Barbuda|NA;V4=São Cristóvão e Neves|NA;8P=Barbados|NA;9Y=Trinidad e Tobago|NA;9Z=Trinidad e Tobago|NA;C6=Bahamas|NA;VP9=Bermudas|NA;
TI=Costa Rica|NA;TE=Costa Rica|NA;HP=Panamá|NA;HO=Panamá|NA;3E=Panamá|NA;3F=Panamá|NA;YN=Nicarágua|NA;HR=Honduras|NA;YS=El Salvador|NA;TG=Guatemala|NA;TD=Guatemala|NA;V3=Belize|NA;
EA=Espanha|EU;EB=Espanha|EU;EC=Espanha|EU;ED=Espanha|EU;EE=Espanha|EU;EF=Espanha|EU;EG=Espanha|EU;EH=Espanha|EU;EA6=Ilhas Baleares|EU;EA8=Ilhas Canárias|AF;CT=Portugal|EU;CS=Portugal|EU;CQ=Portugal|EU;CR=Portugal|EU;CU=Açores|EU;CT3=Madeira|AF;
F=França|EU;TM=França|EU;TK=Córsega|EU;DL=Alemanha|EU;DA=Alemanha|EU;DB=Alemanha|EU;DC=Alemanha|EU;DD=Alemanha|EU;DF=Alemanha|EU;DG=Alemanha|EU;DH=Alemanha|EU;DJ=Alemanha|EU;DK=Alemanha|EU;DM=Alemanha|EU;DN=Alemanha|EU;DO=Alemanha|EU;DP=Alemanha|EU;DQ=Alemanha|EU;DR=Alemanha|EU;
I=Itália|EU;IK=Itália|EU;IZ=Itália|EU;IW=Itália|EU;IU=Itália|EU;IT=Sicília|EU;IS=Sardenha|EU;
G=Inglaterra|EU;M=Inglaterra|EU;2E=Inglaterra|EU;MM=Escócia|EU;GM=Escócia|EU;2M=Escócia|EU;MW=País de Gales|EU;GW=País de Gales|EU;2W=País de Gales|EU;MI=Irlanda do Norte|EU;GI=Irlanda do Norte|EU;EI=Irlanda|EU;EJ=Irlanda|EU;
ON=Bélgica|EU;OO=Bélgica|EU;OP=Bélgica|EU;OQ=Bélgica|EU;OR=Bélgica|EU;OS=Bélgica|EU;OT=Bélgica|EU;PA=Países Baixos|EU;PB=Países Baixos|EU;PC=Países Baixos|EU;PD=Países Baixos|EU;PE=Países Baixos|EU;PF=Países Baixos|EU;PG=Países Baixos|EU;PH=Países Baixos|EU;PI=Países Baixos|EU;LX=Luxemburgo|EU;
HB=Suíça|EU;HE=Suíça|EU;HB0=Liechtenstein|EU;OE=Áustria|EU;OK=Tchéquia|EU;OL=Tchéquia|EU;OM=Eslováquia|EU;HA=Hungria|EU;HG=Hungria|EU;SP=Polônia|EU;SN=Polônia|EU;SO=Polônia|EU;SQ=Polônia|EU;SR=Polônia|EU;3Z=Polônia|EU;
YO=Romênia|EU;YP=Romênia|EU;YQ=Romênia|EU;YR=Romênia|EU;LZ=Bulgária|EU;SV=Grécia|EU;SW=Grécia|EU;SX=Grécia|EU;SY=Grécia|EU;SZ=Grécia|EU;J4=Grécia|EU;9A=Croácia|EU;S5=Eslovênia|EU;E7=Bósnia-Herzegovina|EU;YU=Sérvia|EU;YT=Sérvia|EU;4O=Montenegro|EU;Z3=Macedônia do Norte|EU;ZA=Albânia|EU;
SM=Suécia|EU;SA=Suécia|EU;SB=Suécia|EU;SC=Suécia|EU;SD=Suécia|EU;SE=Suécia|EU;SF=Suécia|EU;SG=Suécia|EU;SH=Suécia|EU;SI=Suécia|EU;SJ=Suécia|EU;SK=Suécia|EU;SL=Suécia|EU;7S=Suécia|EU;8S=Suécia|EU;
LA=Noruega|EU;LB=Noruega|EU;LC=Noruega|EU;LD=Noruega|EU;LE=Noruega|EU;LF=Noruega|EU;LG=Noruega|EU;LH=Noruega|EU;LI=Noruega|EU;LJ=Noruega|EU;LK=Noruega|EU;LL=Noruega|EU;LM=Noruega|EU;OH=Finlândia|EU;OF=Finlândia|EU;OG=Finlândia|EU;OI=Finlândia|EU;OZ=Dinamarca|EU;OU=Dinamarca|EU;OV=Dinamarca|EU;5P=Dinamarca|EU;5Q=Dinamarca|EU;TF=Islândia|EU;
ES=Estônia|EU;YL=Letônia|EU;LY=Lituânia|EU;UA=Rússia|EU;RA=Rússia|EU;RK=Rússia|EU;RN=Rússia|EU;RU=Rússia|EU;RV=Rússia|EU;RW=Rússia|EU;RX=Rússia|EU;RZ=Rússia|EU;UB=Rússia|EU;UC=Rússia|EU;UD=Rússia|EU;UE=Rússia|EU;UF=Rússia|EU;UG=Rússia|EU;UH=Rússia|EU;UI=Rússia|EU;R=Rússia|EU;UA9=Rússia Asiática|AS;RA9=Rússia Asiática|AS;UA0=Rússia Asiática|AS;RA0=Rússia Asiática|AS;UA2=Kaliningrado|EU;
UR=Ucrânia|EU;US=Ucrânia|EU;UT=Ucrânia|EU;UU=Ucrânia|EU;UV=Ucrânia|EU;UW=Ucrânia|EU;UX=Ucrânia|EU;UY=Ucrânia|EU;UZ=Ucrânia|EU;EM=Ucrânia|EU;EN=Ucrânia|EU;EO=Ucrânia|EU;EW=Bielorrússia|EU;EU=Bielorrússia|EU;ER=Moldávia|EU;4L=Geórgia|AS;EK=Armênia|AS;4J=Azerbaijão|AS;4K=Azerbaijão|AS;
TA=Turquia|AS;TB=Turquia|AS;TC=Turquia|AS;YM=Turquia|AS;5B=Chipre|AS;P3=Chipre|AS;H2=Chipre|AS;ZC4=Chipre (Reino Unido)|AS;9H=Malta|EU;1A=Ordem de Malta|EU;
JA=Japão|AS;JE=Japão|AS;JF=Japão|AS;JG=Japão|AS;JH=Japão|AS;JI=Japão|AS;JJ=Japão|AS;JK=Japão|AS;JL=Japão|AS;JM=Japão|AS;JN=Japão|AS;JO=Japão|AS;JP=Japão|AS;JQ=Japão|AS;JR=Japão|AS;JS=Japão|AS;7J=Japão|AS;7K=Japão|AS;7L=Japão|AS;7M=Japão|AS;7N=Japão|AS;8J=Japão|AS;8N=Japão|AS;
HL=Coreia do Sul|AS;DS=Coreia do Sul|AS;DT=Coreia do Sul|AS;6K=Coreia do Sul|AS;6L=Coreia do Sul|AS;6M=Coreia do Sul|AS;6N=Coreia do Sul|AS;
BY=China|AS;BA=China|AS;BD=China|AS;BG=China|AS;BH=China|AS;BI=China|AS;BJ=China|AS;BL=China|AS;BM=China|AS;BO=China|AS;BP=China|AS;BQ=China|AS;BR=China|AS;BS=China|AS;BT=China|AS;BU=China|AS;BV=Taiwan|AS;BX=Taiwan|AS;VR=Hong Kong|AS;XX9=Macau|AS;
VU=Índia|AS;AT=Índia|AS;AU=Índia|AS;AV=Índia|AS;AW=Índia|AS;8T=Índia|AS;8U=Índia|AS;8V=Índia|AS;8W=Índia|AS;8X=Índia|AS;8Y=Índia|AS;
HS=Tailândia|AS;E2=Tailândia|AS;9M=Malásia|AS;9W=Malásia|AS;9V=Singapura|AS;YB=Indonésia|OC;YC=Indonésia|OC;YD=Indonésia|OC;YE=Indonésia|OC;YF=Indonésia|OC;YG=Indonésia|OC;YH=Indonésia|OC;7A=Indonésia|OC;7B=Indonésia|OC;7C=Indonésia|OC;7D=Indonésia|OC;7E=Indonésia|OC;7F=Indonésia|OC;7G=Indonésia|OC;7H=Indonésia|OC;7I=Indonésia|OC;DU=Filipinas|OC;DV=Filipinas|OC;DW=Filipinas|OC;DX=Filipinas|OC;DY=Filipinas|OC;DZ=Filipinas|OC;4D=Filipinas|OC;4E=Filipinas|OC;4F=Filipinas|OC;4G=Filipinas|OC;4H=Filipinas|OC;4I=Filipinas|OC;XV=Vietnã|AS;3W=Vietnã|AS;XU=Camboja|AS;XW=Laos|AS;XY=Mianmar|AS;XZ=Mianmar|AS;
A4=Omã|AS;A6=Emirados Árabes|AS;A7=Catar|AS;A9=Bahrein|AS;9K=Kuwait|AS;HZ=Arábia Saudita|AS;7Z=Arábia Saudita|AS;8Z=Arábia Saudita|AS;4X=Israel|AS;4Z=Israel|AS;JY=Jordânia|AS;OD=Líbano|AS;YK=Síria|AS;YI=Iraque|AS;EP=Irã|AS;EQ=Irã|AS;9N=Nepal|AS;S2=Bangladesh|AS;4S=Sri Lanka|AS;AP=Paquistão|AS;UN=Cazaquistão|AS;UP=Cazaquistão|AS;UQ=Cazaquistão|AS;UK=Uzbequistão|AS;UJ=Uzbequistão|AS;
VK=Austrália|OC;AX=Austrália|OC;VH=Austrália|OC;VI=Austrália|OC;VJ=Austrália|OC;VL=Austrália|OC;VM=Austrália|OC;VN=Austrália|OC;ZL=Nova Zelândia|OC;ZM=Nova Zelândia|OC;YJ=Vanuatu|OC;FK=Nova Caledônia|OC;FO=Polinésia Francesa|OC;3D2=Fiji|OC;P2=Papua Nova Guiné|OC;
ZS=África do Sul|AF;ZR=África do Sul|AF;ZT=África do Sul|AF;ZU=África do Sul|AF;V5=Namíbia|AF;A2=Botsuana|AF;7P=Lesoto|AF;3DA=Eswatini|AF;Z2=Zimbábue|AF;9J=Zâmbia|AF;7Q=Malaui|AF;C9=Moçambique|AF;D2=Angola|AF;9Q=RD Congo|AF;9U=Burundi|AF;9X=Ruanda|AF;5H=Tanzânia|AF;5X=Uganda|AF;5Y=Quênia|AF;ET=Etiópia|AF;E3=Eritreia|AF;6O=Somália|AF;J2=Djibuti|AF;ST=Sudão|AF;SU=Egito|AF;
CN=Marrocos|AF;5A=Líbia|AF;7X=Argélia|AF;3V=Tunísia|AF;TS=Tunísia|AF;CT9=Madeira|AF;D4=Cabo Verde|AF;
5N=Nigéria|AF;5U=Níger|AF;6W=Senegal|AF;TU=Costa do Marfim|AF;9G=Gana|AF;5V=Togo|AF;TY=Benim|AF;TT=Chade|AF;TJ=Camarões|AF;TR=Gabão|AF;TN=Congo|AF;3C=Guiné Equatorial|AF;S9=São Tomé e Príncipe|AF;D6=Comores|AF;5R=Madagascar|AF;3B8=Maurício|AF;3B9=Rodrigues|AF;FR=Reunião|AF;
A3=Tonga|OC;5W=Samoa|OC;T2=Tuvalu|OC;T3=Kiribati|OC;V6=Micronésia|OC;V7=Ilhas Marshall|OC;
OY=Ilhas Faroé|EU;OX=Groenlândia|NA;XP=Groenlândia|NA;
''';

List<MapEntry<String, DxccInfo>>? _table;

List<MapEntry<String, DxccInfo>> _build() {
  final out = <MapEntry<String, DxccInfo>>[];
  for (final item in _raw.replaceAll('\n', '').split(';')) {
    final t = item.trim();
    if (t.isEmpty) continue;
    final kv = t.split('=');
    if (kv.length != 2) continue;
    final cc = kv[1].split('|');
    if (cc.length != 2) continue;
    out.add(MapEntry(kv[0], DxccInfo(cc[0], cc[1])));
  }
  out.sort((a, b) => b.key.length.compareTo(a.key.length));
  return out;
}

/// Remove sufixos/prefixos portáteis e devolve o indicativo base ("PY2XYZ/P" -> "PY2XYZ").
String baseCall(String call) {
  var c = call.toUpperCase().replaceAll(RegExp(r'[<>]'), '');
  if (!c.contains('/')) return c;
  final parts = c.split('/');
  // Escolhe a parte que parece um prefixo de país (a mais curta com dígito) quando é prefixo/indicativo.
  if (parts.length == 2) {
    final a = parts[0], b = parts[1];
    if (['P', 'M', 'MM', 'AM', 'QRP', 'A', 'B'].contains(b) || RegExp(r'^\d$').hasMatch(b)) return a;
    if (a.length <= 3 && RegExp(r'\d').hasMatch(a)) return a; // ex.: EA8/PY2XYZ => EA8
    return b.length >= a.length ? b : a;
  }
  return parts.first;
}

/// Procura o país pelo indicativo. Retorna null se desconhecido.
DxccInfo? lookupDxcc(String call) {
  _table ??= _build();
  final c = baseCall(call);
  if (c.isEmpty) return null;
  for (final e in _table!) {
    if (c.startsWith(e.key)) return e.value;
  }
  return null;
}
