// AUS CURRENTPHOTO UND CURRENTOHOTO+1 IRGENDWIE DOCH LIEBER LINKS UND RECHTS MACHEN
// DETAILANSICHT PRO BILD GEGEN WELCHE ES GEWONNEN ODER VERLOREN HAT

// NACH JEDEM DURCHLAUF MUSS IRGENDWAS AUFBLINKEN DAMIT MAN DAS WEISS
// DIE ROUNDSTATS MUESSEN MIT IN DIE JSON GESPEICHERT WERDEN
// BASEURL AUCH IN DIE JSON
// EINZELFOTO-ANSICH
// FUNKTION DAS MAN DIE SCHLECHTESTEN FOTOS NACHEINANDER AUS DEM ARRAY KILLT (ODER EINFACH NUR N FLAG SETZT)


//var jsonfile = '{ "photos" : [' +
//'{ "id":1 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":2 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":3 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":4 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":5 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":1 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":2 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":3 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":4 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":5 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":1 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":2 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":3 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":4 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":5 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":20 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] } ],' +
//' "stats" : [ { "percent" : 0 }]}';

//var jsonfile = '{ "photos" :' +
//'[{"losses": [], "wins": [], "score": 1000, "id": 0, "uri": "xkopp-venus-15_113-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 1, "uri": "venus_18-122-004.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 2, "uri": "venus_18-123-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 3, "uri": "venus_16_162-027.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 4, "uri": "17_138-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 5, "uri": "venus_16_145-020.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 6, "uri": "17_139-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 7, "uri": "17_124-022.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 8, "uri": "17_129-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 9, "uri": "venus_19-113-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 10, "uri": "venus_19-113-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 11, "uri": "17_138-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 12, "uri": "xkopp-venus-15_112-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 13, "uri": "xkopp-venus-15_113-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 14, "uri": "xkopp-venus-15_113-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 15, "uri": "venus_18-111-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 16, "uri": "17_129-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 17, "uri": "17_138-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 18, "uri": "venus_18-123-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 19, "uri": "xkopp-venus-15_113-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 20, "uri": "venus_19-097-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 21, "uri": "venus_18-123-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 23, "uri": "17_129-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 24, "uri": "17_139-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 25, "uri": "17_139-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 26, "uri": "venus_16_144-022.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 27, "uri": "venus_19-102-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 28, "uri": "venus_18-122-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 29, "uri": "venus_16_145-019.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 30, "uri": "venus_18-122-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 31, "uri": "venus_16_161-024.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 32, "uri": "venus_19-111-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 33, "uri": "venus_16_153-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 34, "uri": "venus_18-121-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 35, "uri": "venus_19-108-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 36, "uri": "venus_19-119-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 37, "uri": "venus_16_161-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 38, "uri": "venus_19-100-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 39, "uri": "17_137-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 40, "uri": "venus_19-100-028.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 41, "uri": "venus_16_161-027.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 42, "uri": "17_122-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 43, "uri": "17_122-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 44, "uri": "venus_19-119-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 45, "uri": "venus_19-104-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 46, "uri": "venus_19-114-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 47, "uri": "xkopp-venus-15_111-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 48, "uri": "venus_16_146-021.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 49, "uri": "venus_16_146-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 50, "uri": "xkopp-venus-15_109-017.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 51, "uri": "venus_19-115-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 52, "uri": "venus_19-115-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 53, "uri": "venus_18-121-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 54, "uri": "venus_18-120-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 55, "uri": "venus_16_161-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 56, "uri": "xkopp-venus-15_109-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 57, "uri": "venus_16_146-024.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 58, "uri": "xkopp-venus-15_109-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 59, "uri": "venus_19-111-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 60, "uri": "venus_16_152-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 61, "uri": "venus_19-109-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 62, "uri": "venus_16_153-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 63, "uri": "venus_19-108-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 64, "uri": "venus_16_152-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 65, "uri": "venus_16_161-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 66, "uri": "venus_19-122-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 67, "uri": "17_119-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 68, "uri": "venus_19-099-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 69, "uri": "venus_19-098-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 70, "uri": "venus_18-120-022.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 71, "uri": "venus_16_161-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 72, "uri": "venus_16_161-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 73, "uri": "venus_16_161-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 74, "uri": "venus_19-101-018.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 75, "uri": "venus_19-104-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 76, "uri": "venus_16_153-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 77, "uri": "venus_16_152-020.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 78, "uri": "17_123-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 79, "uri": "venus_16_161-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 80, "uri": "venus_19-114-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 81, "uri": "venus_16_153-021.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 82, "uri": "venus_18-121-021.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 83, "uri": "venus_16_152-031.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 84, "uri": "venus_19-111-020.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 85, "uri": "venus_16_161-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 86, "uri": "venus_16_161-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 87, "uri": "venus_16_147-028.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 88, "uri": "venus_19-114-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 89, "uri": "venus_19-122-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 90, "uri": "venus_19-105-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 91, "uri": "venus_19-099-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 92, "uri": "venus_19-104-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 93, "uri": "venus_19-114-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 94, "uri": "venus_16_152-026.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 95, "uri": "venus_16_161-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 96, "uri": "venus_16_146-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 97, "uri": "venus_18-123-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 98, "uri": "venus_16_144-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 99, "uri": "xkopp-venus-15_106-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 100, "uri": "xkopp-venus-15_113-019.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 101, "uri": "17_131-026.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 102, "uri": "venus_19-106-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 103, "uri": "venus_19-116-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 104, "uri": "venus_19-116-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 105, "uri": "venus_18-119-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 106, "uri": "venus_16_144-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 107, "uri": "venus_16_149-024.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 108, "uri": "17_129-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 109, "uri": "venus_16_149-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 110, "uri": "venus_19-121-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 111, "uri": "venus_19-116-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 112, "uri": "venus_16_154-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 113, "uri": "venus_16_144-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 114, "uri": "17_124-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 115, "uri": "venus_16_145-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 116, "uri": "xkopp-venus-15_107-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 117, "uri": "venus_18-118-004.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 118, "uri": "venus_16_144-029.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 119, "uri": "venus_16_162-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 120, "uri": "venus_16_162-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 121, "uri": "17_138-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 122, "uri": "venus_16_151-025.jpg"}]'
//+ '}';

var jsonfile = '{"photos":[{"losses":[121,106,74],"wins":[72,50,16,62,8,54,117,7,63],"score":1201.1516363341004,"id":79,"uri":"venus_16_161-003.jpg"},{"losses":[96,25],"wins":[66,33,42,5,108,43,62,61,43,58],"score":1275.6287517831004,"id":69,"uri":"venus_19-098-002.jpg"},{"losses":[4,3,21,101,118,46,74,68,44],"wins":[41,57,100],"score":890.5368077061579,"id":37,"uri":"venus_16_161-025.jpg"},{"losses":[29,112],"wins":[24,120,75,54,115,36,45,16,47,119],"score":1323.4391803900605,"id":91,"uri":"venus_19-099-016.jpg"},{"losses":[3,103,42,43],"wins":[18,19,38,0,63,8,6,56],"score":943.0419519369741,"id":107,"uri":"venus_16_149-024.jpg"},{"losses":[68,33,10,43,91,81,84,54],"wins":[117,111,61,38],"score":869.0635781832142,"id":36,"uri":"venus_19-119-001.jpg"},{"losses":[118,95,33,68,26,93],"wins":[5,2,47,47,85,31],"score":945.7511673732516,"id":86,"uri":"venus_16_161-016.jpg"},{"losses":[63,45,6,93,26,4,74,82,61,28],"wins":[12,60],"score":686.2846986088861,"id":13,"uri":"xkopp-venus-15_113-010.jpg"},{"losses":[28,81,34,84,10,116],"wins":[3,89,120,86,8,118],"score":938.6772393555938,"id":95,"uri":"venus_16_161-015.jpg"},{"losses":[78],"wins":[65,49,37,0,116,103,90,11,75,114,73],"score":1331.7968217227133,"id":101,"uri":"17_131-026.jpg"},{"losses":[80,53,48,74,2,99,53,86,45,68],"wins":[41,8],"score":759.5802833735153,"id":85,"uri":"venus_16_161-002.jpg"},{"losses":[27,18,43,30,101],"wins":[38,114,99,107,6,89,3],"score":1148.2435023725498,"id":103,"uri":"venus_19-116-011.jpg"},{"losses":[43,32,30,15,72,45,45,82,48,18,54,40],"wins":[],"score":661.3679528981716,"id":52,"uri":"venus_19-115-009.jpg"},{"losses":[106,71,26,58,18,103,10,82],"wins":[87,85,87,20],"score":821.4954301724175,"id":99,"uri":"xkopp-venus-15_106-015.jpg"},{"losses":[101,44,80,15,110],"wins":[55,60,51,75,41,51,95],"score":1052.497438178309,"id":116,"uri":"xkopp-venus-15_107-003.jpg"},{"losses":[],"wins":[69,74,89,122,94,82,12,39,73,115,121,51],"score":1379.301151451151,"id":96,"uri":"venus_16_146-012.jpg"},{"losses":[65,10,79,35,58,74,9,2,71,122],"wins":[122,19],"score":695.7659264842807,"id":50,"uri":"xkopp-venus-15_109-017.jpg"},{"losses":[121,67,86,11,88,11,83,118],"wins":[85,57,105,50],"score":818.8607232824836,"id":2,"uri":"venus_18-123-001.jpg"},{"losses":[107,25,118,80],"wins":[97,103,58,55,51,99,82,52],"score":1062.2764835762196,"id":18,"uri":"venus_18-123-003.jpg"},{"losses":[120,18,68,29,66,70,46,108,70],"wins":[114,114,7],"score":893.3507548013455,"id":97,"uri":"venus_18-123-008.jpg"},{"losses":[71,112,119,65,115,119,60,62,113,33,99,77],"wins":[],"score":549.9925231105899,"id":20,"uri":"venus_19-097-011.jpg"},{"losses":[49,6,1,86,66,86,88,21,91,25],"wins":[90,56],"score":787.9283632003605,"id":47,"uri":"xkopp-venus-15_111-015.jpg"},{"losses":[25,10,28,78,69,69],"wins":[52,103,36,75,100,107],"score":1090.3048117082376,"id":43,"uri":"17_122-007.jpg"},{"losses":[61,48,10,31,78,80],"wins":[20,99,117,89,50,76],"score":969.2004212970835,"id":71,"uri":"venus_16_161-010.jpg"},{"losses":[108,15,34,67,30,109,115],"wins":[77,33,57,87,2],"score":921.4107064874877,"id":83,"uri":"venus_16_152-031.jpg"},{"losses":[62,113,31,25,115,102,54,32,9,58],"wins":[100,89],"score":747.3182091682311,"id":98,"uri":"venus_16_144-010.jpg"},{"losses":[],"wins":[64,122,55,92,117,64,64,28,97,94,9,97],"score":1419.1743723689297,"id":70,"uri":"venus_18-120-022.jpg"},{"losses":[9,69,9,1,46],"wins":[59,24,62,59,55,107,49],"score":1203.1231590050243,"id":42,"uri":"17_122-006.jpg"},{"losses":[21,81,70,88],"wins":[41,14,39,33,33,111,87,31],"score":1122.3741426221036,"id":92,"uri":"venus_19-104-012.jpg"},{"losses":[93,120,28,40,10],"wins":[54,100,39,98,14,76,77],"score":1042.9368599610548,"id":102,"uri":"venus_19-106-005.jpg"},{"losses":[28,74,69,49],"wins":[83,77,122,57,72,120,97,87],"score":1152.998484286394,"id":108,"uri":"17_129-023.jpg"},{"losses":[17],"wins":[23,63,91,35,97,121,105,105,39,48,38],"score":1300.5657961394859,"id":29,"uri":"venus_16_145-019.jpg"},{"losses":[49,91,9,96],"wins":[89,51,39,20,98,24,59,83],"score":1135.6220859021355,"id":115,"uri":"venus_16_145-012.jpg"},{"losses":[15,92,88,16,116,37,1,85,63,30,90,48],"wins":[],"score":577.775331800229,"id":41,"uri":"venus_16_161-027.jpg"},{"losses":[69,10,68],"wins":[94,109,19,47,55,97,35,81,14],"score":1212.703909934602,"id":66,"uri":"venus_19-122-014.jpg"},{"losses":[34,80,79,121,91,25,67],"wins":[62,41,14,12,39],"score":968.6130358688058,"id":16,"uri":"17_129-016.jpg"},{"losses":[42,45,42,115,45],"wins":[114,8,12,76,76,31,57],"score":974.7928480849747,"id":59,"uri":"venus_19-111-003.jpg"},{"losses":[],"wins":[101,109,31,7,104,43,40,71,53,34,55,112],"score":1427.4836702035423,"id":78,"uri":"17_123-023.jpg"},{"losses":[59,64,11,97,103,97,23,35,64,101,81],"wins":[8],"score":705.9739810596667,"id":114,"uri":"17_124-011.jpg"},{"losses":[74,73,115,102,32,92,96,16,29,24],"wins":[5,57],"score":771.5441747275896,"id":39,"uri":"17_137-023.jpg"},{"losses":[88,28,88],"wins":[111,98,105,87,65,20,87,4,94],"score":1128.0592710778194,"id":113,"uri":"venus_16_144-016.jpg"},{"losses":[64,54,106,36,24,32,112,69,88],"wins":[90,71,13],"score":820.8755647891693,"id":61,"uri":"venus_19-109-005.jpg"},{"losses":[26,116,73,13,15,111,106,3,109],"wins":[20,19,51],"score":812.6247173277793,"id":60,"uri":"venus_16_152-006.jpg"},{"losses":[66,7,40,55,96,104,93,117,4,70,30,113],"wins":[],"score":654.3470895464068,"id":94,"uri":"venus_16_152-026.jpg"},{"losses":[102,109,91,15,79,40],"wins":[76,105,61,98,52,36],"score":991.1645895900522,"id":54,"uri":"venus_18-120-011.jpg"},{"losses":[],"wins":[111,2,19,1,119,8,90,83,26,26,72,16],"score":1349.8782843939919,"id":67,"uri":"17_119-011.jpg"},{"losses":[77,69,83,7,92,104,92,11],"wins":[36,86,20,19],"score":842.7908343692219,"id":33,"uri":"venus_16_153-012.jpg"},{"losses":[112,78,66,6,49,84,46],"wins":[54,12,76,83,60],"score":1027.9211772792132,"id":109,"uri":"venus_16_149-025.jpg"},{"losses":[12,54,62,46,89,59,109,59,102,117,71],"wins":[56],"score":643.6215116318822,"id":76,"uri":"venus_16_153-025.jpg"},{"losses":[82,48,36,71,70,24,84,118,79,72],"wins":[94,76],"score":731.6537045090367,"id":117,"uri":"venus_18-118-004.jpg"},{"losses":[70,70,70,106],"wins":[114,61,40,77,118,111,114,44],"score":1204.9668999773962,"id":64,"uri":"venus_16_152-013.jpg"},{"losses":[67,113,75,36,26,64,92,45,1],"wins":[87,60,0],"score":816.1732264347252,"id":111,"uri":"venus_19-116-006.jpg"},{"losses":[25,58,59,63,95,67,107,79,114,112,75,85],"wins":[],"score":574.7214155163367,"id":8,"uri":"17_129-001.jpg"},{"losses":[],"wins":[41,83,3,52,60,56,54,0,116,104,21,90],"score":1331.9488546745895,"id":15,"uri":"venus_18-111-008.jpg"},{"losses":[67],"wins":[58,90,47,90,0,41,42,119,110,5,111],"score":1296.4419816850514,"id":1,"uri":"venus_18-122-004.jpg"},{"losses":[46],"wins":[50,43,66,36,71,77,21,21,99,95,102],"score":1336.8451226727898,"id":10,"uri":"venus_19-113-001.jpg"},{"losses":[44,9,30,80,29],"wins":[117,85,71,4,3,52,41],"score":1062.108647446486,"id":48,"uri":"venus_16_146-021.jpg"},{"losses":[],"wins":[87,103,57,14,23,5,19,55,104,62,74,9],"score":1387.7377733271328,"id":27,"uri":"venus_19-102-002.jpg"},{"losses":[78,80,27,15,88],"wins":[0,11,9,30,94,33,14],"score":1058.6988046282893,"id":104,"uri":"venus_19-116-013.jpg"},{"losses":[],"wins":[8,43,14,34,98,46,69,18,12,105,16,47],"score":1399.1519121557292,"id":25,"uri":"17_139-013.jpg"},{"losses":[110,66],"wins":[12,92,82,26,55,82,95,36,63,114],"score":1251.6246130534214,"id":81,"uri":"venus_16_153-021.jpg"},{"losses":[68],"wins":[85,55,16,4,93,35,104,116,48,71,18],"score":1352.8658875581411,"id":80,"uri":"venus_19-114-010.jpg"},{"losses":[7,115,116,44,3,18,89,3,90,116,60,96],"wins":[],"score":599.5466674569476,"id":51,"uri":"venus_19-115-008.jpg"},{"losses":[106,96,101],"wins":[6,39,60,110,9,58,93,0,122],"score":1180.4270242087034,"id":73,"uri":"venus_16_161-006.jpg"},{"losses":[40,17,116,91,84,34,43,101],"wins":[111,6,8,0],"score":912.3609711275445,"id":75,"uri":"venus_19-104-001.jpg"},{"losses":[17,25,27,92,16,106,121,102,122,66,104],"wins":[105],"score":666.841384194057,"id":14,"uri":"xkopp-venus-15_113-006.jpg"},{"losses":[73,82,75,107,28,103,82,34],"wins":[47,109,13,89],"score":816.5471038245446,"id":6,"uri":"17_139-001.jpg"},{"losses":[79,44,35,17,17,77,108,53,67],"wins":[89,52,117],"score":842.652006186542,"id":72,"uri":"venus_16_161-012.jpg"},{"losses":[116,80,70,18,81,66,27,40,42,78,30],"wins":[94],"score":769.8258653450346,"id":55,"uri":"venus_16_161-023.jpg"},{"losses":[84],"wins":[113,41,23,113,2,38,92,47,32,104,61],"score":1309.2262272220962,"id":88,"uri":"venus_19-114-007.jpg"},{"losses":[61,1,53,47,1,106,67,101,44,15],"wins":[51,41],"score":820.7584424677826,"id":90,"uri":"venus_19-105-002.jpg"},{"losses":[93,35,67,106,1,49,91],"wins":[20,38,20,32,58],"score":993.7749799695467,"id":119,"uri":"venus_16_162-003.jpg"},{"losses":[91,95,32,108],"wins":[97,24,102,35,100,58,31,12],"score":1101.7234678709528,"id":120,"uri":"venus_16_162-002.jpg"},{"losses":[115,95,96,72,6,31,71,74,103,98],"wins":[76,51],"score":669.5969808621397,"id":89,"uri":"venus_19-122-011.jpg"},{"losses":[80,21,48,30,7,113,121],"wins":[37,0,65,13,94],"score":869.862525578403,"id":4,"uri":"17_138-005.jpg"},{"losses":[57,70,50,96,108,53,68,110,65,73],"wins":[14,50],"score":819.9091982678489,"id":122,"uri":"venus_16_151-025.jpg"},{"losses":[68,27,121,83,23,2,108,37,59,112,39],"wins":[122],"score":610.3458248283548,"id":57,"uri":"venus_16_146-024.jpg"},{"losses":[103,40,107,119,40,88,23,36,53,29],"wins":[65,5],"score":774.4626774675269,"id":38,"uri":"venus_19-100-002.jpg"},{"losses":[46,78],"wins":[109,20,91,12,19,100,11,61,8,57],"score":1183.5294527283042,"id":112,"uri":"venus_16_154-002.jpg"},{"losses":[1,110,18,73,45,120,119,69],"wins":[8,99,50,98],"score":890.4813868516073,"id":58,"uri":"xkopp-venus-15_109-014.jpg"},{"losses":[16,93,46,42,79,69,27,93,35],"wins":[98,76,20],"score":793.2673245690298,"id":62,"uri":"venus_16_153-003.jpg"},{"losses":[95,15,110,48,44,106,103],"wins":[37,51,107,51,60],"score":977.8756295111774,"id":3,"uri":"venus_16_162-027.jpg"},{"losses":[30,29,80,120,66,28],"wins":[119,72,50,114,56,62],"score":987.6279929709629,"id":35,"uri":"venus_19-108-010.jpg"},{"losses":[104,17,63,110,112,101],"wins":[32,114,2,2,33,65],"score":1049.1268427348175,"id":11,"uri":"17_138-010.jpg"},{"losses":[17],"wins":[53,88,5,56,82,75,117,87,109,95,36],"score":1266.8019598239014,"id":84,"uri":"venus_19-111-020.jpg"},{"losses":[64],"wins":[48,72,0,51,105,26,116,53,3,90,37],"score":1258.6509676209514,"id":44,"uri":"venus_19-119-016.jpg"},{"losses":[9,81,44,67,67],"wins":[60,56,99,13,111,86,21],"score":1148.2738968609729,"id":26,"uri":"venus_16_144-022.jpg"},{"losses":[91,42,120,121,115,110,93],"wins":[77,117,61,39,53],"score":1014.4191985263868,"id":24,"uri":"17_139-012.jpg"},{"losses":[45,30,78,30,40,59,86,120,92],"wins":[98,71,89],"score":824.0865835257283,"id":31,"uri":"venus_16_161-024.jpg"},{"losses":[49,9,10,10,15,26],"wins":[92,118,37,19,4,47],"score":968.0257488098231,"id":21,"uri":"venus_18-123-007.jpg"},{"losses":[104,73,70,27],"wins":[42,26,48,42,21,50,115,98],"score":1161.3259108648956,"id":9,"uri":"venus_19-113-015.jpg"},{"losses":[101,4,53,38,118,113,77,11],"wins":[50,20,122,0],"score":797.0345163631029,"id":65,"uri":"venus_16_161-011.jpg"},{"losses":[29,107,46,23,81,79],"wins":[13,87,8,11,56,41],"score":945.064690520155,"id":63,"uri":"venus_19-108-001.jpg"},{"losses":[105,107,67,21,66,112,27,60,100,121,50,33],"wins":[],"score":578.1401885897602,"id":19,"uri":"xkopp-venus-15_113-007.jpg"},{"losses":[45,78,97,23,49,79],"wins":[51,94,33,77,4,105],"score":977.5878179736114,"id":7,"uri":"17_124-022.jpg"},{"losses":[106,81,84,96,81,18],"wins":[117,6,52,13,6,99],"score":1050.4116096700582,"id":82,"uri":"venus_18-121-021.jpg"},{"losses":[91],"wins":[31,13,7,105,59,52,52,58,85,111,59],"score":1246.2065686034837,"id":45,"uri":"venus_19-104-009.jpg"},{"losses":[98,46,102,34,68,112,120,43,37],"wins":[5,19,5],"score":802.0599296524296,"id":100,"uri":"xkopp-venus-15_113-019.jpg"},{"losses":[70,17],"wins":[5,108,93,113,43,102,95,6,35,13],"score":1258.2413181550094,"id":28,"uri":"venus_18-122-001.jpg"},{"losses":[],"wins":[36,57,97,87,56,100,122,86,80,37,85,66],"score":1387.4661917943502,"id":68,"uri":"venus_19-099-013.jpg"},{"losses":[14,54,45,44,113,29,2,29,25,23,7],"wins":[19],"score":715.4974838559181,"id":105,"uri":"venus_18-119-013.jpg"},{"losses":[96,49,27,110],"wins":[39,108,85,79,50,37,13,89],"score":1079.2926200682894,"id":74,"uri":"venus_19-101-018.jpg"},{"losses":[104],"wins":[35,31,52,31,103,4,48,83,41,94,55],"score":1283.7182418046664,"id":30,"uri":"venus_18-122-014.jpg"},{"losses":[],"wins":[14,75,34,118,11,72,72,29,0,49,28,84],"score":1492.0631286821774,"id":17,"uri":"17_138-007.jpg"},{"losses":[28,86,84,100,69,27,39,38,93,118,1,100],"wins":[],"score":588.7582982213448,"id":5,"uri":"venus_16_145-020.jpg"},{"losses":[101,17,42],"wins":[47,23,115,74,21,108,109,7,119],"score":1185.2621631994461,"id":49,"uri":"venus_16_146-025.jpg"},{"losses":[27,99,63,68,111,83,113,84,99,113,92,108],"wins":[],"score":626.3680834569182,"id":87,"uri":"venus_16_147-028.jpg"},{"losses":[73,1],"wins":[81,56,58,3,34,11,122,24,116,74],"score":1249.2501751671196,"id":110,"uri":"venus_19-121-001.jpg"},{"losses":[25],"wins":[10,100,112,76,62,37,63,42,97,109,32],"score":1329.5145300347212,"id":46,"uri":"venus_19-114-009.jpg"},{"losses":[],"wins":[99,82,79,73,61,90,14,119,60,12,3,64],"score":1385.5539934332978,"id":106,"uri":"venus_16_144-013.jpg"},{"losses":[64,78,32],"wins":[75,38,94,38,31,102,55,54,52],"score":1094.9413754302775,"id":40,"uri":"venus_19-100-028.jpg"},{"losses":[34,110,26,84,68,15,63,47,76,107,35,23],"wins":[],"score":609.1480583328697,"id":56,"uri":"xkopp-venus-15_109-016.jpg"},{"losses":[29,96],"wins":[2,79,118,57,24,16,14,77,19,4],"score":1202.9734387049375,"id":121,"uri":"17_138-008.jpg"},{"losses":[84,44,78,24],"wins":[85,90,32,65,122,85,72,38],"score":1023.8546018293549,"id":53,"uri":"venus_18-121-014.jpg"},{"losses":[11,23,53,119,88,46],"wins":[52,39,120,61,98,40],"score":1058.0129320161989,"id":32,"uri":"venus_19-111-006.jpg"},{"losses":[24,83,108,64,7,10,121,102],"wins":[33,72,65,20],"score":890.0368366711131,"id":77,"uri":"venus_16_152-020.jpg"},{"losses":[28,80,73],"wins":[119,102,62,13,94,5,24,62,86],"score":1189.3919985800896,"id":93,"uri":"venus_19-114-006.jpg"},{"losses":[29,49,88,27],"wins":[32,57,114,7,38,63,105,56],"score":1163.9483312339833,"id":23,"uri":"17_129-006.jpg"},{"losses":[81,13,59,112,109,96,16,25,106,34,120],"wins":[76],"score":707.1255568341728,"id":12,"uri":"xkopp-venus-15_112-001.jpg"},{"losses":[21,121,17,95,64],"wins":[86,37,65,117,5,18,2],"score":1117.7870875785113,"id":118,"uri":"venus_16_144-029.jpg"},{"losses":[17,25,110,78],"wins":[56,16,100,83,75,95,12,6],"score":1180.8483468676418,"id":34,"uri":"venus_18-121-013.jpg"},{"losses":[104,4,44,107,101,1,111,15,17,73,65,75],"wins":[],"score":646.9153938327244,"id":0,"uri":"xkopp-venus-15_113-005.jpg"}]}';

var json = JSON.parse(jsonfile);
var currentPhoto = -2;
var points = $.map(json.photos, function(value, index){
        return [value];
    });
var correctAnswer = 0;
var round = 1;
var baseUrl = "photos/venuskopf/";

// The maximum number of points a player goes up or down by
// A 50% chance of winning (aka, both players have the same rating) means they go up or down by 32/2 = 16 points.
//var KFactor = 32
KFactor = 128
var getChanceOfWinning = 0
var chances = 0



function shuffle(array) {
  var currentIndex = array.length, temporaryValue, randomIndex;

  // While there remain elements to shuffle...
  while (0 !== currentIndex) {

    // Pick a remaining element...
    randomIndex = Math.floor(Math.random() * currentIndex);
    currentIndex -= 1;

    // And swap it with the current element.
    temporaryValue = array[currentIndex];
    array[currentIndex] = array[randomIndex];
    array[randomIndex] = temporaryValue;
  }

  return array;
}

function makeTable() {
  
  points.sort(function(a, b){
    var a1= a.score, b1= b.score;
    if(a1== b1) return 0;
    return a1< b1? 1: -1;
  });

  $("#completeTable table").empty();
  $("#completeTable table").append("<tr class=line><th>#</th><th>NAME</th><th>W</th><th>L</th><th>ELO</th></tr>")
  for (var i = 0; i < points.length; i++) {
  
    if ((i == Math.floor(points.length*0.25-1)) || (i == Math.floor(points.length*0.50-1)) || (i == Math.floor(points.length*0.75-1))) {
 
      if ((json.photos[currentPhoto].id == points[i].id) || (json.photos[currentPhoto+1].id == points[i].id)) {
        $("#completeTable table").append("<tr class=\"highlight line\"><td>" + (i+1) + ".</td><td>" + points[i].uri + "</td><td>" + points[i].wins.length + "</td><td>" + points[i].losses.length + "</td><td>" + points[i].score.toFixed(0) + "</td></tr>")
      } else {
        $("#completeTable table").append("<tr class=line><td>" + (i+1) + ".</td><td>" + points[i].uri + "</td><td>" + points[i].wins.length + "</td><td>" + points[i].losses.length + "</td><td>" + points[i].score.toFixed(0) + "</td></tr>")
      } 
    } else {
      
      if ((json.photos[currentPhoto].id == points[i].id) || (json.photos[currentPhoto+1].id == points[i].id)) {
        $("#completeTable table").append("<tr class=highlight><td>" + (i+1) + ".</td><td>" + points[i].uri + "</td><td>" + points[i].wins.length + "</td><td>" + points[i].losses.length + "</td><td>" + points[i].score.toFixed(0) + "</td></tr>")
      } else {
        $("#completeTable table").append("<tr><td>" + (i+1) + ".</td><td>" + points[i].uri + "</td><td>" + points[i].wins.length + "</td><td>" + points[i].losses.length + "</td><td>" + points[i].score.toFixed(0) + "</td></tr>")
      }
      
    }  
    
  }

}

function makeRoundStats() {

  percent = correctAnswer*100/(currentPhoto/2);

  $("#round").html("<table><tr><td>ROUND " + round + "</td><td>" + (currentPhoto/2) + "/" + (json.photos.length/2) + "</td></tr></table>");
  
  if (isNaN(percent)) {
    $("#roundAccuracy").text("0%");
  } else {
    $("#roundAccuracy").text(percent.toFixed(0) + "%");
  }

}

function updatePhotos() {

  // CHECK LENGTH
  if (currentPhoto == (json.photos.length-2)) {
    shuffle(json.photos);
    currentPhoto = 0;
    correctAnswer = 0;
    $("#roundStats table").append("<tr><td>ROUND " + round + "</td><td>" + percent.toFixed(0) + "%</td></tr>");
    round++;
    console.log(percent.toFixed(0) + "%")
    console.log("NEW SHUFFLE")
  } else { currentPhoto += 2; }
 
  // The actual Elo formula -- returns the probability of winning (num between 0 and 1)
  getChanceOfWinning = (opponentRating, selfRating) => 1 / (1 + Math.pow(10, (opponentRating - selfRating) / 400))

  // Chances
  chances = {
    left: getChanceOfWinning(json.photos[currentPhoto+1].score, json.photos[currentPhoto].score),
    right: getChanceOfWinning(json.photos[currentPhoto].score, json.photos[currentPhoto+1].score)
  } 
 
  // Output
  $("#leftPhoto").attr("src",baseUrl + json.photos[currentPhoto].uri);
  $("#rightPhoto").attr("src",baseUrl + json.photos[currentPhoto+1].uri);
   
  $("#previewLeftPhoto").attr("src",baseUrl + json.photos[currentPhoto].uri);
  $("#previewRightPhoto").attr("src",baseUrl + json.photos[currentPhoto+1].uri);
 
  $("#leftStats .name").text(json.photos[currentPhoto].uri + " (" + json.photos[currentPhoto].wins.length + "-" + json.photos[currentPhoto].losses.length + ")");
  $("#leftStats .chance").text((chances.left*100).toFixed(0) + "%");
  $("#leftStats .score").text(json.photos[currentPhoto].score.toFixed(0));

  $("#rightStats .name").text(json.photos[currentPhoto+1].uri + " (" + json.photos[currentPhoto+1].wins.length + "-" + json.photos[currentPhoto+1].losses.length + ")");
  $("#rightStats .chance").text((chances.right*100).toFixed(0) + "%");
  $("#rightStats .score").text(json.photos[currentPhoto+1].score.toFixed(0));


  makeTable();
  
  makeRoundStats();

}


function saveJson(text, filename){
  var a = document.createElement('a');
  a.setAttribute('href', 'data:text/plain;charset=utf-8,'+encodeURIComponent(text));
  a.setAttribute('download', filename);
  a.click()
}

$("#download").click(function() {
  saveJson(JSON.stringify(json), "filename.json");
});


function leftPhotoWins() {

  // DEBUGS
  console.log(json.photos[currentPhoto].uri + " (S:" + json.photos[currentPhoto].score.toFixed(0) + "|C:" + chances.left.toFixed(2) + "|W:" + json.photos[currentPhoto].wins.length + "|L:" + json.photos[currentPhoto].losses.length + ") wins against " + json.photos[currentPhoto+1].uri + " (S:" + json.photos[currentPhoto+1].score.toFixed(0) + "|C:" + chances.right.toFixed(2) + "|W:" + json.photos[currentPhoto+1].wins.length + "|L:" + json.photos[currentPhoto+1].losses.length + ").");

  // LEFT WINS
  json.photos[currentPhoto].wins.push(json.photos[currentPhoto+1].id);
  json.photos[currentPhoto+1].losses.push(json.photos[currentPhoto].id);
 
  // If left photo wins:
  json.photos[currentPhoto].score = json.photos[currentPhoto].score + KFactor * (1 - chances.left)
  json.photos[currentPhoto+1].score = json.photos[currentPhoto+1].score + KFactor * (0 - chances.right) 

  if (chances.left > chances.right) {
    correctAnswer++
  }  

  updatePhotos();
}

function rightPhotoWins() {

  // DEBUGS
  console.log(json.photos[currentPhoto+1].uri + " (S:" + json.photos[currentPhoto+1].score.toFixed(0) + "|C:" + chances.right.toFixed(2) + "|W:" + json.photos[currentPhoto+1].wins.length + "|L:" + json.photos[currentPhoto+1].losses.length + ") wins against " + json.photos[currentPhoto].uri + " (S:" + json.photos[currentPhoto].score.toFixed(0) + "|C:" + chances.left.toFixed(2) + "|W:" + json.photos[currentPhoto].wins.length + "|L:" + json.photos[currentPhoto].losses.length + ").");

  // RIGHT WINS
  json.photos[currentPhoto+1].wins.push(json.photos[currentPhoto].id);
  json.photos[currentPhoto].losses.push(json.photos[currentPhoto+1].id);
  
  // If right photowins:
  json.photos[currentPhoto+1].score = json.photos[currentPhoto+1].score + KFactor * (1 - chances.right)
  json.photos[currentPhoto].score = json.photos[currentPhoto].score + KFactor * (0 - chances.left)
    
  if (chances.right > chances.left) {
    correctAnswer++
  }  
    
  updatePhotos();

}



function showRanking() {

  $("#grid").empty();
  $("#canvas").show();

  for (var i = 0; i < points.length; i++) {
  
    if (i == 0) {
      $("#grid").append("<h2>&starf;&starf;&starf;&starf;</h2>");
    }
  
    if (i == Math.floor(points.length*0.25)) {
      $("#grid").append("<h2>&starf;&starf;&starf;</h2>");
    }
    
    if (i == Math.floor(points.length*0.50)) {
      $("#grid").append("<h2>&starf;&starf;</h2>");
    }
    
    if (i == Math.floor(points.length*0.75)) {
      $("#grid").append("<h2>&starf;</h2>");
    }   
    
    $("#grid").append("<div class=\"gridItem\"><img src=" + baseUrl + "" + points[i].uri + "></div>");

  
  }

}




$("#leftPhoto").click(function() {

  leftPhotoWins();

});

$("#rightPhoto").click(function() {

  rightPhotoWins();
  
});

$("#ranking").click(function() {

  showRanking();
  
});

$("#rate").click(function() {

  $("#canvas").hide();
  
});

// KEYBOARD SHORTCUTS
$('html').keydown(function(e) {

  if (e.keyCode == 37) { leftPhotoWins(); } // LEFT
  if (e.keyCode == 39) { rightPhotoWins(); } // RIGHT

});


// FULLSCREEN
function activateFullscreen(element) {
  if (element.requestFullscreen) { element.requestFullscreen(); } // W3C spec
  else if (element.mozRequestFullScreen) { element.mozRequestFullScreen(); } // Firefox
  else if (element.webkitRequestFullscreen) { element.webkitRequestFullscreen(); } // Safari
  else if(element.msRequestFullscreen) { element.msRequestFullscreen(); } // IE/Edge
};

$('#fullscreen').on('click', function() {
 
    activateFullscreen(document.documentElement);
   
});



// INIT
shuffle(json.photos);
updatePhotos();


