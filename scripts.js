// DETAILANSICHT PRO BILD GEGEN WELCHE ES GEWONNEN ODER VERLOREN HAT
// EINSTELLUNGSSEITE FUER EINSTELLUNGEN WIE K-WERT, WELCHE RUNDE WAS AUSGEBLENDET WIRD, ETC


//var jsonfile = '{ "photos" : [' +
//'{ "id":1 , "uri":"test-1.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":2 , "uri":"test-2.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":3 , "uri":"test-3.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":4 , "uri":"test-4.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":5 , "uri":"test-5.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":6 , "uri":"test-6.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":7 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":8 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":9 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":10 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":11 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":12 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":13 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":14 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":15 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 },' +
//'{ "id":6 , "uri":"test-6.jpg" , "score":1000 , "wins":[] , "losses":[] , "killed":0 } ],' +
//' "killed" : [], "rounds" : [], "currentState" : [ { "currentPhoto": 0 , "correctAnswer": 0 } ], "meta" : [ { "baseUrl": "photos/" } ]}';

var jsonfile = '{ "photos" :' +
'[{"wins": [], "losses": [], "uri": "17_138-011.jpg", "killed": "", "score": 1000, "id": 0}, {"wins": [], "losses": [], "uri": "venus_16_163-022.jpg", "killed": "", "score": 1000, "id": 1}, {"wins": [], "losses": [], "uri": "venus_16_155-021.jpg", "killed": "", "score": 1000, "id": 2}, {"wins": [], "losses": [], "uri": "venus_16_158-016.jpg", "killed": "", "score": 1000, "id": 3}, {"wins": [], "losses": [], "uri": "venus_19-103-001.jpg", "killed": "", "score": 1000, "id": 4}, {"wins": [], "losses": [], "uri": "17_143-013.jpg", "killed": "", "score": 1000, "id": 5}, {"wins": [], "losses": [], "uri": "venus_18-118-021.jpg", "killed": "", "score": 1000, "id": 6}, {"wins": [], "losses": [], "uri": "17_131-011.jpg", "killed": "", "score": 1000, "id": 7}, {"wins": [], "losses": [], "uri": "17_131-005.jpg", "killed": "", "score": 1000, "id": 8}, {"wins": [], "losses": [], "uri": "venus_16_151-017.jpg", "killed": "", "score": 1000, "id": 9}, {"wins": [], "losses": [], "uri": "venus_16_162-024.jpg", "killed": "", "score": 1000, "id": 10}, {"wins": [], "losses": [], "uri": "venus_19-113-003.jpg", "killed": "", "score": 1000, "id": 11}, {"wins": [], "losses": [], "uri": "venus_19-103-017.jpg", "killed": "", "score": 1000, "id": 12}, {"wins": [], "losses": [], "uri": "17_139-017.jpg", "killed": "", "score": 1000, "id": 13}, {"wins": [], "losses": [], "uri": "17_139-002.jpg", "killed": "", "score": 1000, "id": 14}, {"wins": [], "losses": [], "uri": "17_128-013.jpg", "killed": "", "score": 1000, "id": 15}, {"wins": [], "losses": [], "uri": "venus-15_111-013.jpg", "killed": "", "score": 1000, "id": 16}, {"wins": [], "losses": [], "uri": "venus_19-112-013.jpg", "killed": "", "score": 1000, "id": 17}, {"wins": [], "losses": [], "uri": "venus_19-121-024.jpg", "killed": "", "score": 1000, "id": 18}, {"wins": [], "losses": [], "uri": "17_125-009.jpg", "killed": "", "score": 1000, "id": 19}, {"wins": [], "losses": [], "uri": "venus_18-110-009.jpg", "killed": "", "score": 1000, "id": 20}, {"wins": [], "losses": [], "uri": "17_142-010.jpg", "killed": "", "score": 1000, "id": 21}, {"wins": [], "losses": [], "uri": "venus-15_115-008.jpg", "killed": "", "score": 1000, "id": 22}, {"wins": [], "losses": [], "uri": "17_131-017.jpg", "killed": "", "score": 1000, "id": 23}, {"wins": [], "losses": [], "uri": "venus_19-117-019.jpg", "killed": "", "score": 1000, "id": 24}, {"wins": [], "losses": [], "uri": "venus_19-103-011.jpg", "killed": "", "score": 1000, "id": 25}, {"wins": [], "losses": [], "uri": "venus_16_155-024.jpg", "killed": "", "score": 1000, "id": 26}, {"wins": [], "losses": [], "uri": "venus_19-112-015.jpg", "killed": "", "score": 1000, "id": 27}, {"wins": [], "losses": [], "uri": "venus_16_150-029.jpg", "killed": "", "score": 1000, "id": 28}, {"wins": [], "losses": [], "uri": "venus_16_161-018.jpg", "killed": "", "score": 1000, "id": 29}, {"wins": [], "losses": [], "uri": "venus_19-111-012.jpg", "killed": "", "score": 1000, "id": 30}, {"wins": [], "losses": [], "uri": "venus_18-120-016.jpg", "killed": "", "score": 1000, "id": 31}, {"wins": [], "losses": [], "uri": "venus_16_152-003.jpg", "killed": "", "score": 1000, "id": 32}, {"wins": [], "losses": [], "uri": "venus_18-121-012.jpg", "killed": "", "score": 1000, "id": 33}, {"wins": [], "losses": [], "uri": "venus_19-119-015.jpg", "killed": "", "score": 1000, "id": 34}, {"wins": [], "losses": [], "uri": "venus_16_164-014.jpg", "killed": "", "score": 1000, "id": 35}, {"wins": [], "losses": [], "uri": "17_141-001.jpg", "killed": "", "score": 1000, "id": 36}, {"wins": [], "losses": [], "uri": "venus_19-110-002.jpg", "killed": "", "score": 1000, "id": 37}, {"wins": [], "losses": [], "uri": "venus_16_147-025.jpg", "killed": "", "score": 1000, "id": 38}, {"wins": [], "losses": [], "uri": "venus-15_107-008.jpg", "killed": "", "score": 1000, "id": 39}, {"wins": [], "losses": [], "uri": "venus_16_153-004.jpg", "killed": "", "score": 1000, "id": 40}, {"wins": [], "losses": [], "uri": "17_140-013.jpg", "killed": "", "score": 1000, "id": 41}, {"wins": [], "losses": [], "uri": "17_127-022.jpg", "killed": "", "score": 1000, "id": 42}, {"wins": [], "losses": [], "uri": "venus_19-111-014.jpg", "killed": "", "score": 1000, "id": 43}, {"wins": [], "losses": [], "uri": "venus_19-119-012.jpg", "killed": "", "score": 1000, "id": 44}, {"wins": [], "losses": [], "uri": "venus_19-105-008.jpg", "killed": "", "score": 1000, "id": 45}, {"wins": [], "losses": [], "uri": "venus_19-099-008.jpg", "killed": "", "score": 1000, "id": 46}, {"wins": [], "losses": [], "uri": "venus_16_164-012.jpg", "killed": "", "score": 1000, "id": 47}, {"wins": [], "losses": [], "uri": "17_141-013.jpg", "killed": "", "score": 1000, "id": 48}, {"wins": [], "losses": [], "uri": "17_140-016.jpg", "killed": "", "score": 1000, "id": 49}, {"wins": [], "losses": [], "uri": "venus_16_157-023.jpg", "killed": "", "score": 1000, "id": 50}, {"wins": [], "losses": [], "uri": "venus_19-111-017.jpg", "killed": "", "score": 1000, "id": 51}, {"wins": [], "losses": [], "uri": "17_132-015.jpg", "killed": "", "score": 1000, "id": 52}, {"wins": [], "losses": [], "uri": "venus_16_157-022.jpg", "killed": "", "score": 1000, "id": 53}, {"wins": [], "losses": [], "uri": "venus_19-100-007.jpg", "killed": "", "score": 1000, "id": 54}, {"wins": [], "losses": [], "uri": "17_127-018.jpg", "killed": "", "score": 1000, "id": 55}, {"wins": [], "losses": [], "uri": "17_127-024.jpg", "killed": "", "score": 1000, "id": 56}, {"wins": [], "losses": [], "uri": "venus_18-116-009.jpg", "killed": "", "score": 1000, "id": 57}, {"wins": [], "losses": [], "uri": "venus_16_143-027.jpg", "killed": "", "score": 1000, "id": 58}, {"wins": [], "losses": [], "uri": "venus_16_164-021.jpg", "killed": "", "score": 1000, "id": 59}, {"wins": [], "losses": [], "uri": "venus_19-100-023.jpg", "killed": "", "score": 1000, "id": 60}, {"wins": [], "losses": [], "uri": "venus_16_152-009.jpg", "killed": "", "score": 1000, "id": 61}, {"wins": [], "losses": [], "uri": "venus_19-122-017.jpg", "killed": "", "score": 1000, "id": 62}, {"wins": [], "losses": [], "uri": "17_132-027.jpg", "killed": "", "score": 1000, "id": 63}, {"wins": [], "losses": [], "uri": "venus-15_106-011.jpg", "killed": "", "score": 1000, "id": 64}, {"wins": [], "losses": [], "uri": "venus_19-100-008.jpg", "killed": "", "score": 1000, "id": 65}, {"wins": [], "losses": [], "uri": "17_127-017.jpg", "killed": "", "score": 1000, "id": 66}, {"wins": [], "losses": [], "uri": "17_137-003.jpg", "killed": "", "score": 1000, "id": 67}, {"wins": [], "losses": [], "uri": "venus_16_146-028.jpg", "killed": "", "score": 1000, "id": 68}, {"wins": [], "losses": [], "uri": "venus_16_152-030.jpg", "killed": "", "score": 1000, "id": 69}, {"wins": [], "losses": [], "uri": "venus-15_107-004.jpg", "killed": "", "score": 1000, "id": 70}, {"wins": [], "losses": [], "uri": "venus_19-110-025.jpg", "killed": "", "score": 1000, "id": 71}, {"wins": [], "losses": [], "uri": "17_137-012.jpg", "killed": "", "score": 1000, "id": 72}, {"wins": [], "losses": [], "uri": "17_127-004.jpg", "killed": "", "score": 1000, "id": 73}, {"wins": [], "losses": [], "uri": "17_141-018.jpg", "killed": "", "score": 1000, "id": 74}, {"wins": [], "losses": [], "uri": "venus_19-104-013.jpg", "killed": "", "score": 1000, "id": 75}, {"wins": [], "losses": [], "uri": "venus_19-099-017.jpg", "killed": "", "score": 1000, "id": 76}, {"wins": [], "losses": [], "uri": "venus-15_107-006.jpg", "killed": "", "score": 1000, "id": 77}, {"wins": [], "losses": [], "uri": "venus_19-106-010.jpg", "killed": "", "score": 1000, "id": 78}, {"wins": [], "losses": [], "uri": "venus_16_144-004.jpg", "killed": "", "score": 1000, "id": 79}, {"wins": [], "losses": [], "uri": "17_129-009.jpg", "killed": "", "score": 1000, "id": 80}, {"wins": [], "losses": [], "uri": "venus_16_149-032.jpg", "killed": "", "score": 1000, "id": 81}, {"wins": [], "losses": [], "uri": "venus_19-120-011.jpg", "killed": "", "score": 1000, "id": 82}, {"wins": [], "losses": [], "uri": "venus_19-106-007.jpg", "killed": "", "score": 1000, "id": 83}, {"wins": [], "losses": [], "uri": "venus_16_150-027.jpg", "killed": "", "score": 1000, "id": 84}, {"wins": [], "losses": [], "uri": "venus_18-110-010.jpg", "killed": "", "score": 1000, "id": 85}, {"wins": [], "losses": [], "uri": "venus_16_149-018.jpg", "killed": "", "score": 1000, "id": 86}, {"wins": [], "losses": [], "uri": "venus_19-117-007.jpg", "killed": "", "score": 1000, "id": 87}, {"wins": [], "losses": [], "uri": "venus_16_163-011.jpg", "killed": "", "score": 1000, "id": 88}, {"wins": [], "losses": [], "uri": "17_142-025.jpg", "killed": "", "score": 1000, "id": 89}, {"wins": [], "losses": [], "uri": "venus_18-109-003.jpg", "killed": "", "score": 1000, "id": 90}, {"wins": [], "losses": [], "uri": "17_131-020.jpg", "killed": "", "score": 1000, "id": 91}, {"wins": [], "losses": [], "uri": "venus_16_150-009.jpg", "killed": "", "score": 1000, "id": 92}, {"wins": [], "losses": [], "uri": "venus_16_148-027.jpg", "killed": "", "score": 1000, "id": 93}, {"wins": [], "losses": [], "uri": "venus_16_163-007.jpg", "killed": "", "score": 1000, "id": 94}, {"wins": [], "losses": [], "uri": "17_139-025.jpg", "killed": "", "score": 1000, "id": 95}]'
+ ', "killed" : [], "rounds" : [], "currentState" : [ { "currentPhoto": 0 , "correctAnswer": 0 } ], "meta" : [ { "baseUrl": "photos/venuscloseupsfinal/" } ]}';

// JSON VON 18-RUNDEN VENUSKOPP
// var jsonfile = '{"photos":[{"wins":[83,8,65,33,40,35,109,59],"losses":[49,109,25,79,15,95,34,48,16,49,34],"uri":"venus_19-104-009.jpg","killed":"","score":917.5127861807216,"id":45},{"wins":[119,75,90,113,98,63,37,7,42,58,91,7,75,44,34,107],"losses":[48,1,46],"uri":"venus_19-114-006.jpg","killed":"","score":1409.7552122793709,"id":93},{"wins":[117,77,38,72,39,26,37],"losses":[64,29,15,92,80,30,74,78,121,106,67,112],"uri":"17_129-023.jpg","killed":"","score":982.3730328439476,"id":108},{"wins":[8,7,54,5,89,3,44,26],"losses":[70,74,69,113,46,106,34,93,69,66,69],"uri":"venus_19-099-016.jpg","killed":"","score":1044.1136321244633,"id":91},{"wins":[41,62,62,26,7,53,85],"losses":[104,17,96,73,23,46,91,106,70,88,29,88],"uri":"venus_16_162-027.jpg","killed":"","score":975.1726729425395,"id":3},{"wins":[82,38,41,76,118,7,33,4,44,35,34,39,74,16],"losses":[28,84,1,92,69],"uri":"venus_19-121-001.jpg","killed":"","score":1255.9987627914975,"id":110},{"wins":[76,61,16,52,51,122,53,35,3,24,35,26,35,4,37,116],"losses":[30,96,15],"uri":"17_129-006.jpg","killed":"","score":1284.7756065973315,"id":23},{"wins":[102,76,117,5,99,53,58,40,71,6],"losses":[84,95,80,9,70,95,29,118,29],"uri":"17_138-010.jpg","killed":"","score":981.695703963569,"id":11},{"wins":[32,54,118,117,83,65,118,82,16,42,112,48],"losses":[113,88,29,49,25,79,64],"uri":"17_122-007.jpg","killed":"","score":1214.1234329696956,"id":43},{"wins":[75,43,114,44,26,91,83,44,4,115,10,26,7],"losses":[25,68,93,34,101,46],"uri":"venus_16_144-016.jpg","killed":"","score":1223.9250052509456,"id":113},{"wins":[45,59,85,109,77,40,95,43,39,86,24,45,118],"losses":[73,29,30,96,78,28],"uri":"venus_16_146-025.jpg","killed":"","score":1259.9372939881407,"id":49},{"wins":[34,110,20,112,56,40,65,120,7,86,82,4,63,32,120,49,63],"losses":[101,64],"uri":"venus_18-122-001.jpg","killed":"","score":1422.3751304568395,"id":28},{"wins":[111,20,60,102,40,31,99,38,115,115,109],"losses":[67,79,28,49,29,67,15,96],"uri":"venus_16_161-016.jpg","killed":"","score":1058.4190519527779,"id":86},{"wins":[93,97,119,76,103,54,36,77,99,102,53,45,102,4],"losses":[74,69,44,30,43],"uri":"venus_16_146-021.jpg","killed":"","score":1115.6566695575352,"id":48},{"wins":[89,99,83,6,115,6,18,16,53,53],"losses":[107,70,34,101,93,106,43,25,101],"uri":"17_122-006.jpg","killed":"","score":1111.9710365642622,"id":42},{"wins":[16,100,7,103,21,24,26,83,35,21],"losses":[43,92,118,101,73,84,92,28,80],"uri":"venus_19-111-006.jpg","killed":"","score":1125.9864747987601,"id":32},{"wins":[12,59,10,51,40,36,75,53],"losses":[10,93,48,92,104,10,78,17,9,1,92],"uri":"venus_16_162-003.jpg","killed":"","score":1052.4462729140714,"id":119},{"wins":[100,120,0,120,8,0,111,75,60,10,72,7,15,118,7],"losses":[78,96,107,23],"uri":"xkopp-venus-15_107-003.jpg","killed":"","score":1179.5025439974568,"id":116},{"wins":[16,89,10,107,33,37,79,95,72,91,42,3,79,24,108,95,68,80],"losses":[67],"uri":"venus_16_144-013.jpg","killed":"","score":1570.0520127629825,"id":106},{"wins":[79,108,57,6,81,28,60,60,36,77,21,74,6,63,43,18],"losses":[73,25,1],"uri":"venus_16_152-013.jpg","killed":"","score":1332.3483321968808,"id":64},{"wins":[33,10,53,11,120,69,110,98,32,37,107,114,7,31,18,34,16,4],"losses":[70],"uri":"venus_19-111-020.jpg","killed":"","score":1469.6655256936097,"id":84},{"wins":[114,4,90,11,38,16,37,45,37,21,11,115],"losses":[88,101,68,106,49,106,30],"uri":"venus_16_161-015.jpg","killed":"","score":1212.4286280240067,"id":95},{"wins":[61,112,91,99,48,21,108,83,36],"losses":[78,66,70,68,64,30,34,110,66,104],"uri":"venus_19-101-018.jpg","killed":"","score":980.7412121568451,"id":74},{"wins":[50,102,81,21,19,24,60,108,53,81,115,104,7],"losses":[80,88,1,68,67,70],"uri":"17_138-008.jpg","killed":"","score":1273.6221415126006,"id":121},{"wins":[13,53,44,114,115,74,2,62,2,114,9,102,10,112,37,91,74,75],"losses":[88],"uri":"venus_19-122-014.jpg","killed":"","score":1448.8171905904153,"id":66},{"wins":[56,55,71,2,40],"losses":[17,91,32,27,110,3,93,28,116,84,93,116,113,121],"uri":"17_124-022.jpg","killed":"","score":885.611425763283,"id":7},{"wins":[59,122,50,113,34,47,20,29,45,16,54,30,64,101,43,35,42,112,88],"losses":[],"uri":"17_139-013.jpg","killed":"","score":1582.4466905448091,"id":25},{"wins":[99,18,74,99,116,31,47,41,103,15,119,108,10,9,49,80,104,44,73],"losses":[],"uri":"17_123-023.jpg","killed":"","score":1605.561108426434,"id":78},{"wins":[71,85,76,49,35,98,64,3,32,77,30,75,104,54,36,88,69,10],"losses":[78],"uri":"venus_16_161-006.jpg","killed":"","score":1476.8252359234987,"id":73},{"wins":[21,9,65,23,18,49,82,108,115,112,40,74,48,31,21,95],"losses":[68,73,25],"uri":"venus_18-122-014.jpg","killed":"","score":1418.0111983937675,"id":30},{"wins":[115,47,53,57,40,86,39,59,45,103,120,85,43,85,81,44],"losses":[64,106,106],"uri":"venus_16_161-003.jpg","killed":"","score":1353.8970155881025,"id":79},{"wins":[53,89,0,114,2,75,47,63,2,108],"losses":[74,28,101,30,92,66,69,43,25],"uri":"venus_16_154-002.jpg","killed":"","score":1059.995735201812,"id":112},{"wins":[21,33,98,61,109,8,91,36,48,21,91,112,110,91],"losses":[84,27,17,88,73],"uri":"venus_19-098-002.jpg","killed":"","score":1336.3468073909232,"id":69},{"wins":[63,31,35,63,6,42,117,113,59,91,45,74,45],"losses":[28,25,96,110,84,93],"uri":"venus_18-121-013.jpg","killed":"","score":1213.9789442433273,"id":34},{"wins":[37,115,89,32,102,82,18,6,21,11],"losses":[29,43,110,43,120,116,92,9,49],"uri":"venus_16_144-029.jpg","killed":"","score":1033.3814065027645,"id":118},{"wins":[118,13,108,57,49,33,43,88,104,39,6,102,86,3,11,102,11],"losses":[96,25],"uri":"venus_16_145-019.jpg","killed":"","score":1439.8334243093498,"id":29},{"wins":[52,2,53,21,51,72,11,39,63,72,119,63,118],"losses":[1,30,66,78,27,1],"uri":"venus_19-113-015.jpg","killed":"","score":1169.6450030481396,"id":9},{"wins":[72,51,97,85,57,115,6,45],"losses":[106,32,23,68,25,95,43,42,92,84,110],"uri":"17_129-016.jpg","killed":"","score":974.31232376941,"id":16},{"wins":[61,97,8,85,37,71,102],"losses":[25,49,10,119,44,96,79,34,77,1,109,45],"uri":"venus_19-111-003.jpg","killed":"","score":921.3119017308499,"id":59},{"wins":[39,45,77,117,58,71,75,59,31],"losses":[115,27,69,49,45,26,18,68,86,17],"uri":"venus_16_149-025.jpg","killed":"","score":1052.801730057244,"id":109},{"wins":[35,3,44,41,62,119,85,62,111,114,120,21,74],"losses":[15,101,29,73,78,121],"uri":"venus_19-116-013.jpg","killed":"","score":1178.069097809708,"id":104},{"wins":[28,50,81,58,95,120,104,32,51,42,1,112,57,4,113,42,31],"losses":[25,96],"uri":"17_131-026.jpg","killed":"","score":1409.9444985750995,"id":101},{"wins":[58,90,121,77,39,41,11,108,56,98,88,83,24,39,81,32],"losses":[70,78,106],"uri":"venus_19-114-010.jpg","killed":"","score":1327.8999583232485,"id":80},{"wins":[14,71,65,72,31,83,85],"losses":[113,93,37,26,112,116,73,17,109,93,119,66],"uri":"venus_19-104-001.jpg","killed":"","score":925.1829425672634,"id":75},{"wins":[119,59,47,53,38,119,44,81,36,35],"losses":[84,106,119,116,78,66,113,17,73],"uri":"venus_19-113-001.jpg","killed":"","score":1092.2521757191703,"id":10},{"wins":[97,111,31,54,36],"losses":[34,96,46,34,1,93,112,9,1,28,9,64,96,28],"uri":"venus_19-108-001.jpg","killed":"","score":932.8826001779578,"id":63},{"wins":[57,91,102,42,27,90,84,33,74,58,80,11,2,3,53,83,121,18,67],"losses":[],"uri":"venus_18-120-022.jpg","killed":"","score":1569.098057084741,"id":70},{"wins":[20,57,72,120,82,24,114],"losses":[11,121,70,86,118,48,66,29,107,48,29,59],"uri":"venus_19-106-005.jpg","killed":"","score":881.0104888314133,"id":102},{"wins":[7,15,12,3,71,41,115,46,114,69,58,75,119,103,54,10,1,109],"losses":[67],"uri":"17_138-007.jpg","killed":"","score":1475.5986315887146,"id":17},{"wins":[0,63,5,71,72,29,3,34,59,24,49,114,54,23,54,116,101,63,86],"losses":[],"uri":"venus_16_146-012.jpg","killed":"","score":1563.467479249846,"id":96},{"wins":[90,19,47,35,109,85],"losses":[78,46,30,107,107,26,118,42,44,84,1,70,64],"uri":"venus_18-123-003.jpg","killed":"","score":896.8048959088027,"id":18},{"wins":[120,19,56,17,115,86,60,103,21,106,121,26,27,31,107,81,86,108],"losses":[70],"uri":"17_119-011.jpg","killed":"","score":1474.560213460701,"id":67},{"wins":[5,58,33,118,103,115],"losses":[67,116,107,116,84,101,102,28,44,79,104,28,92],"uri":"venus_16_162-002.jpg","killed":"","score":1015.2778535371331,"id":120},{"wins":[55,47,32,90,108,38,119,111,41,110,32,35,112,71,118,16,120,119],"losses":[27],"uri":"venus_19-104-012.jpg","killed":"","score":1411.3925794237628,"id":92},{"wins":[2,55,60,59,98,54,120,48,18],"losses":[66,104,113,10,113,110,91,93,78,79],"uri":"venus_19-119-016.jpg","killed":"","score":977.2103163374945,"id":44},{"wins":[15,87,63,14,18,39,81,91,3,93,103,81,15,88,35,113],"losses":[15,17,68],"uri":"venus_19-114-009.jpg","killed":"","score":1421.3758297441404,"id":46},{"wins":[36,71,109,89,7,4,92,15,69,117,117,107,26,21,9,37],"losses":[70,67,68],"uri":"venus_19-102-002.jpg","killed":"","score":1396.6224242842281,"id":27},{"wins":[9,65,93,5,77,72,63,121,110,4,77,63,59,64,119,18,9],"losses":[101,17],"uri":"venus_18-122-004.jpg","killed":"","score":1377.5633281984392,"id":1},{"wins":[5,77,6,95,66,56,121,43,81,15,69,103,3,3],"losses":[29,80,73,46,25],"uri":"venus_19-114-007.jpg","killed":"","score":1238.932670518603,"id":88},{"wins":[87,42,120,36,58,62,18,18,103,81,81,102,115,116],"losses":[106,84,27,67,93],"uri":"venus_16_149-024.jpg","killed":"","score":1266.907486619787,"id":107},{"wins":[30,82,41,33,113,117,95,16,117,121,39,85,74,109,27,46,15,26],"losses":[106],"uri":"venus_19-099-013.jpg","killed":"","score":1460.3329381972826,"id":68},{"wins":[104,108,82,46,37,54,45,33,23,86,81],"losses":[46,17,27,78,88,116,46,68],"uri":"venus_18-111-008.jpg","killed":"","score":1248.6883706312672,"id":15}],"killed":[{"wins":[98,37,59],"losses":[88,80,1,108,109,49,48,73,64,1],"uri":"venus_16_152-020.jpg","killed":12,"score":874.1041059908226,"id":77},{"wins":[72,24,122,94,8,75,71,18,109],"losses":[3,113,67,23,32,108,27,113,91,68],"uri":"venus_16_144-022.jpg","killed":18,"score":869.8687169797661,"id":26},{"wins":[31,58,2,99,54],"losses":[101,121,64,46,88,107,10,107,46,121,67,80,79,15],"uri":"venus_16_153-021.jpg","killed":18,"score":867.9619226229719,"id":81},{"wins":[122,62,89,111,31],"losses":[95,39,54,27,37,114,1,110,113,28,101,23,48,84],"uri":"17_138-005.jpg","killed":18,"score":865.3742089238824,"id":4},{"wins":[57,14,76,58,71],"losses":[27,37,107,48,69,64,74,119,63,73,10],"uri":"venus_19-119-001.jpg","killed":15,"score":820.1788557869112,"id":36},{"wins":[55,122,114,20,62],"losses":[6,26,21,121,96,23,102,32,80,106,49],"uri":"17_139-012.jpg","killed":15,"score":819.8467711082126,"id":24},{"wins":[105,36,75,4,65,117],"losses":[118,77,106,15,93,84,95,95,59,66,108,23,27],"uri":"venus_16_161-025.jpg","killed":18,"score":815.8515381456207,"id":37},{"wins":[41,40,57,60],"losses":[104,34,73,54,18,45,23,23,92,110,23,25,32,46,10],"uri":"venus_19-108-010.jpg","killed":18,"score":815.4311673878225,"id":35},{"wins":[],"losses":[74,23,59,69],"uri":"venus_19-109-005.jpg","killed":3,"score":811.6328618088824,"id":61},{"wins":[],"losses":[85,75,36,46],"uri":"xkopp-venus-15_113-006.jpg","killed":3,"score":811.6328618088824,"id":14},{"wins":[2,38,47,56,57,111],"losses":[81,34,115,78,86,63,75,67,84,4,30,109,101],"uri":"venus_16_161-024.jpg","killed":18,"score":810.462359267894,"id":31},{"wins":[109,31,6,40],"losses":[79,118,67,66,42,17,30,86,16,86,113,121,107,95,120],"uri":"venus_16_145-012.jpg","killed":18,"score":807.8510659833412,"id":115},{"wins":[51,8,24,47],"losses":[69,30,121,9,74,67,32,64,118,69,95,104,27,30,32],"uri":"venus_18-123-007.jpg","killed":18,"score":799.021873028706,"id":21},{"wins":[],"losses":[107,46,65,38],"uri":"venus_16_147-028.jpg","killed":3,"score":797.735635996646,"id":87},{"wins":[],"losses":[40,54,17,119],"uri":"xkopp-venus-15_112-001.jpg","killed":3,"score":797.6206149047669,"id":12},{"wins":[51,4,98,51],"losses":[109,80,53,46,79,9,68,29,49,108,80,110],"uri":"17_137-023.jpg","killed":15,"score":797.1826453959713,"id":39},{"wins":[97,12,4,35],"losses":[43,91,48,15,44,81,25,63,96,73,96,17],"uri":"venus_18-120-011.jpg","killed":15,"score":796.5613632646389,"id":54},{"wins":[],"losses":[47,8,97,26],"uri":"venus_16_152-026.jpg","killed":3,"score":794.8645534735396,"id":94},{"wins":[],"losses":[65,9,33,23],"uri":"venus_19-115-009.jpg","killed":3,"score":794.6193242814584,"id":52},{"wins":[105,117,50,65,33],"losses":[103,45,42,43,113,74,71,80,75,32,70],"uri":"venus_16_152-031.jpg","killed":15,"score":793.6676973512539,"id":83},{"wins":[83,20,19,71],"losses":[40,48,32,67,78,107,53,79,46,88,17,120],"uri":"venus_19-116-011.jpg","killed":15,"score":793.1006092795375,"id":103},{"wins":[],"losses":[116,114,72,32],"uri":"xkopp-venus-15_113-019.jpg","killed":3,"score":789.1332273901407,"id":100},{"wins":[13,50,76],"losses":[110,68,111,15,30,118,102,43,53,28],"uri":"venus_18-121-021.jpg","killed":12,"score":785.5801641939571,"id":82},{"wins":[],"losses":[92,44,24,7],"uri":"venus_16_161-023.jpg","killed":3,"score":785.4131621298696,"id":55},{"wins":[],"losses":[37,117,83,60],"uri":"venus_18-119-013.jpg","killed":3,"score":781.5175741179786,"id":105},{"wins":[13,19,8],"losses":[44,31,9,81,112,66,66,112,7,70],"uri":"venus_18-123-001.jpg","killed":12,"score":781.179909153943,"id":2},{"wins":[39,41,103,82],"losses":[112,66,84,79,9,10,23,11,48,121,70,42,3,119,42],"uri":"venus_18-121-014.jpg","killed":18,"score":768.640723530514,"id":53},{"wins":[],"losses":[66,29,2,82],"uri":"xkopp-venus-15_113-010.jpg","killed":3,"score":766.6456706038709,"id":13},{"wins":[52,57],"losses":[84,69,68,106,45,29,70,83,110,120,15],"uri":"venus_16_153-012.jpg","killed":12,"score":764.3625690567042,"id":33},{"wins":[14,50,98,0,114,60,114],"losses":[73,49,16,104,71,59,68,18,79,79,75,3],"uri":"venus_16_161-002.jpg","killed":18,"score":762.9507410047592,"id":85},{"wins":[0,82,56,60,117],"losses":[86,63,116,92,40,4,104,31],"uri":"venus_19-116-006.jpg","killed":12,"score":762.8187471161697,"id":111},{"wins":[122],"losses":[78,72,42,78,74,81,11,86,48],"uri":"xkopp-venus-15_106-015.jpg","killed":9,"score":760.4962295529957,"id":99},{"wins":[122,85,83],"losses":[73,27,75,96,17,103,7,26,36,109,11,92,59],"uri":"venus_16_161-010.jpg","killed":15,"score":757.2330530471745,"id":71},{"wins":[100,90,4],"losses":[95,113,66,24,112,85,17,66,96,84,104,102,85],"uri":"17_124-011.jpg","killed":15,"score":756.7488478333236,"id":114},{"wins":[56,87],"losses":[110,58,31,92,108,10,95,86],"uri":"venus_19-100-002.jpg","killed":9,"score":755.2307082706576,"id":38},{"wins":[24,62,97,8],"losses":[88,64,42,34,42,115,40,118,29,16,11,64],"uri":"17_139-001.jpg","killed":15,"score":755.0909521608232,"id":6},{"wins":[12,103,51,111,6],"losses":[35,86,79,45,28,49,119,11,30,115,7],"uri":"venus_19-100-028.jpg","killed":15,"score":754.5587589061228,"id":40},{"wins":[52,87],"losses":[1,30,45,75,43,83,28,37],"uri":"venus_16_161-011.jpg","killed":9,"score":753.0503181484008,"id":65},{"wins":[],"losses":[18,80,95,92,93,70,114],"uri":"venus_19-105-002.jpg","killed":6,"score":749.3134087027569,"id":90},{"wins":[38,0],"losses":[80,81,101,107,36,120,109,70,11,17,93],"uri":"xkopp-venus-15_109-014.jpg","killed":12,"score":749.0317572108166,"id":58},{"wins":[19],"losses":[6,3,3,4,104,107,24,66,104],"uri":"venus_16_153-003.jpg","killed":9,"score":745.1670286258917,"id":62},{"wins":[],"losses":[42,106,112,27,118,4,91],"uri":"venus_19-122-011.jpg","killed":6,"score":744.1503330196332,"id":89},{"wins":[],"losses":[60,86,103,28,102,24,25],"uri":"venus_19-097-011.jpg","killed":6,"score":739.4308840055841,"id":20},{"wins":[],"losses":[96,111,116,112,58,85,116],"uri":"xkopp-venus-15_113-005.jpg","killed":6,"score":737.4618091768937,"id":0},{"wins":[94],"losses":[54,48,63,6,16,59],"uri":"venus_18-123-008.jpg","killed":6,"score":735.6886947684086,"id":97},{"wins":[],"losses":[77,60,69,39,85,73,93,44,84,80],"uri":"venus_16_144-010.jpg","killed":9,"score":735.2875750408319,"id":98},{"wins":[94],"losses":[92,79,18,10,25,78,31,112,21],"uri":"xkopp-venus-15_111-015.jpg","killed":9,"score":733.5395458594169,"id":47},{"wins":[],"losses":[23,11,73,48,110,36,82],"uri":"venus_16_153-025.jpg","killed":6,"score":732.4230388466186,"id":76},{"wins":[105],"losses":[108,11,83,43,68,111,109,68,34,27,27,37],"uri":"venus_18-118-004.jpg","killed":12,"score":731.1758227335276,"id":117},{"wins":[50],"losses":[38,7,67,111,88,28,57,80,31],"uri":"xkopp-venus-15_109-016.jpg","killed":9,"score":727.9538452940404,"id":56},{"wins":[],"losses":[88,51,96,1,11,91,120],"uri":"venus_16_145-020.jpg","killed":6,"score":725.7039664913754,"id":5},{"wins":[20,98,105],"losses":[86,44,111,67,64,64,116,35,121,85],"uri":"venus_16_152-006.jpg","killed":12,"score":724.5839416915455,"id":60},{"wins":[99,100],"losses":[26,16,96,1,102,9,106,75,108,116,9],"uri":"venus_16_161-012.jpg","killed":12,"score":712.9796776684545,"id":72},{"wins":[],"losses":[3,35,68,110,104,80,17,78,53,92],"uri":"venus_16_161-027.jpg","killed":9,"score":707.1101210130604,"id":41},{"wins":[5],"losses":[39,21,40,16,23,9,39,101,119],"uri":"venus_19-115-008.jpg","killed":9,"score":699.2102630660281,"id":51},{"wins":[],"losses":[62,67,18,103,2,121,57],"uri":"xkopp-venus-15_113-007.jpg","killed":6,"score":690.0345617623266,"id":19},{"wins":[],"losses":[4,25,26,24,71,99,23],"uri":"venus_16_151-025.jpg","killed":6,"score":688.3125339236027,"id":122},{"wins":[19,56],"losses":[70,36,64,29,79,102,16,35,33,31,101],"uri":"venus_16_146-024.jpg","killed":12,"score":681.5539456095659,"id":57},{"wins":[],"losses":[121,101,25,85,56,82,83],"uri":"xkopp-venus-15_109-017.jpg","killed":6,"score":679.2265843854193,"id":50},{"wins":[94],"losses":[91,45,21,26,116,69,59,2,6],"uri":"17_129-001.jpg","killed":9,"score":666.9883993014809,"id":8}],"rounds":[{"percent":"0"},{"percent":"42"},{"percent":"63"},{"percent":"72"},{"percent":"82"},{"percent":"84"},{"percent":"87"},{"percent":"90"},{"percent":"88"},{"percent":"88"},{"percent":"84"},{"percent":"78"},{"percent":"98"},{"percent":"93"},{"percent":"88"},{"percent":"90"},{"percent":"100"},{"percent":"80"},{"percent":"86"}],"currentState":[{"currentPhoto":0,"correctAnswer":0}],"meta":[{"baseUrl":"photos/venuskopf/"}]}'

//var jsonfile = '{"photos":[{"wins":[194],"losses":[21],"uri":"venus_16_153-004.jpg","killed":"","score":1000,"id":106},{"wins":[59,239],"losses":[],"uri":"venus_18-116-015.jpg","killed":"","score":1128,"id":87},{"wins":[248],"losses":[217],"uri":"17_139-002.jpg","killed":"","score":1000,"id":24},{"wins":[149],"losses":[34],"uri":"venus_18-111-022.jpg","killed":"","score":1022.5666136950704,"id":8},{"wins":[],"losses":[18,232],"uri":"venus_16_163-008.jpg","killed":"","score":872,"id":25},{"wins":[126],"losses":[136],"uri":"venus_18-121-010.jpg","killed":"","score":1000,"id":101},{"wins":[100],"losses":[201],"uri":"17_131-020.jpg","killed":"","score":1022.5666136950704,"id":265},{"wins":[46],"losses":[56],"uri":"17_139-006.jpg","killed":"","score":977.4333863049296,"id":44},{"wins":[209,77],"losses":[],"uri":"venus_16_152-003.jpg","killed":"","score":1128,"id":79},{"wins":[182,244],"losses":[],"uri":"venus_19-110-002.jpg","killed":"","score":1105.4333863049296,"id":93},{"wins":[],"losses":[30,86],"uri":"venus_14_97-012-fussel.jpg","killed":"","score":872,"id":193},{"wins":[262],"losses":[148],"uri":"venus_19-106-007.jpg","killed":"","score":1022.5666136950704,"id":231},{"wins":[24,249],"losses":[],"uri":"venus_16_144-004.jpg","killed":"","score":1105.4333863049296,"id":217},{"wins":[121],"losses":[209],"uri":"venus_19-104-019.jpg","killed":"","score":977.4333863049296,"id":119},{"wins":[],"losses":[141,155],"uri":"venus_18-120-023.jpg","killed":"","score":894.5666136950704,"id":154},{"wins":[183],"losses":[233],"uri":"17_131-016.jpg","killed":"","score":1022.5666136950704,"id":71},{"wins":[206],"losses":[111],"uri":"venus-15_106-013.jpg","killed":"","score":1000,"id":156},{"wins":[],"losses":[112,194],"uri":"venus_12_39-010.jpg","killed":"","score":872,"id":43},{"wins":[81],"losses":[145],"uri":"venus_19-097-022.jpg","killed":"","score":1000,"id":282},{"wins":[],"losses":[250,197],"uri":"venus_16_147-012.jpg","killed":"","score":894.5666136950704,"id":162},{"wins":[],"losses":[151,200],"uri":"venus_18-109-017.jpg","killed":"","score":894.5666136950704,"id":263},{"wins":[],"losses":[275,93],"uri":"venus_16_162-004.jpg","killed":"","score":894.5666136950704,"id":244},{"wins":[13,263],"losses":[],"uri":"venus_19-104-013.jpg","killed":"","score":1105.4333863049296,"id":200},{"wins":[196],"losses":[83],"uri":"venus_16_148-013.jpg","killed":"","score":1000,"id":62},{"wins":[272],"losses":[133],"uri":"17_127-005.jpg","killed":"","score":1000,"id":211},{"wins":[150,54],"losses":[],"uri":"venus_18-118-021.jpg","killed":"","score":1105.4333863049296,"id":14},{"wins":[259,30],"losses":[],"uri":"venus_16_163-011.jpg","killed":"","score":1128,"id":256},{"wins":[171,264],"losses":[],"uri":"venus_18-116-009.jpg","killed":"","score":1105.4333863049296,"id":153},{"wins":[142],"losses":[29],"uri":"venus_16_143-015.jpg","killed":"","score":1000,"id":127},{"wins":[26],"losses":[60],"uri":"17_127-010.jpg","killed":"","score":1000,"id":192},{"wins":[159],"losses":[52],"uri":"17_131-005.jpg","killed":"","score":1022.5666136950704,"id":17},{"wins":[51],"losses":[27],"uri":"venus_19-111-007.jpg","killed":"","score":1000,"id":90},{"wins":[],"losses":[149,117],"uri":"17_141-022.jpg","killed":"","score":872,"id":164},{"wins":[],"losses":[37,141],"uri":"venus_14_100-011-fussel.jpg","killed":"","score":894.5666136950704,"id":229},{"wins":[120],"losses":[85],"uri":"venus_19-117-007.jpg","killed":"","score":1000,"id":251},{"wins":[51],"losses":[60],"uri":"venus_19-118-007.jpg","killed":"","score":1000,"id":105},{"wins":[251,268],"losses":[],"uri":"venus_19-119-015.jpg","killed":"","score":1128,"id":85},{"wins":[104,267],"losses":[],"uri":"venus_19-120-019.jpg","killed":"","score":1128,"id":32},{"wins":[130,115],"losses":[],"uri":"17_132-027.jpg","killed":"","score":1105.4333863049296,"id":170},{"wins":[166],"losses":[225],"uri":"venus_16_164-014.jpg","killed":"","score":1000,"id":88},{"wins":[15,23],"losses":[],"uri":"venus_19-103-011.jpg","killed":"","score":1128,"id":58},{"wins":[264],"losses":[171],"uri":"17_135-003.jpg","killed":"","score":977.4333863049296,"id":278},{"wins":[1],"losses":[64],"uri":"17_129-008.jpg","killed":"","score":977.4333863049296,"id":223},{"wins":[131],"losses":[6],"uri":"17_124-001.jpg","killed":"","score":1000,"id":241},{"wins":[108],"losses":[253],"uri":"venus-15_105-012.jpg","killed":"","score":1000,"id":247},{"wins":[13],"losses":[98],"uri":"venus-15_106-003.jpg","killed":"","score":1000,"id":205},{"wins":[226],"losses":[191],"uri":"venus_18-120-006.jpg","killed":"","score":1000,"id":144},{"wins":[92],"losses":[73],"uri":"venus_16_148-007.jpg","killed":"","score":1000,"id":61},{"wins":[234,190],"losses":[],"uri":"17_125-012.jpg","killed":"","score":1105.4333863049296,"id":224},{"wins":[42,166],"losses":[],"uri":"venus_16_162-024.jpg","killed":"","score":1105.4333863049296,"id":19},{"wins":[37],"losses":[67],"uri":"17_120-002.jpg","killed":"","score":1022.5666136950704,"id":12},{"wins":[142,59],"losses":[],"uri":"venus-15_111-002.jpg","killed":"","score":1105.4333863049296,"id":47},{"wins":[],"losses":[267,157],"uri":"venus-15_114-005.jpg","killed":"","score":894.5666136950704,"id":280},{"wins":[],"losses":[93,70],"uri":"17_137-013.jpg","killed":"","score":894.5666136950704,"id":182},{"wins":[39],"losses":[277],"uri":"venus_19-111-012.jpg","killed":"","score":1000,"id":76},{"wins":[],"losses":[238,144],"uri":"venus_18-110-006.jpg","killed":"","score":872,"id":226},{"wins":[175,266],"losses":[],"uri":"17_125-009.jpg","killed":"","score":1105.4333863049296,"id":48},{"wins":[],"losses":[224,137],"uri":"venus_14_97-004-fussel.jpg","killed":"","score":894.5666136950704,"id":234},{"wins":[195,2],"losses":[],"uri":"17_129-009.jpg","killed":"","score":1105.4333863049296,"id":220},{"wins":[],"losses":[268,148],"uri":"venus_19-100-008.jpg","killed":"","score":894.5666136950704,"id":178},{"wins":[],"losses":[5,241],"uri":"venus_19-109-013.jpg","killed":"","score":872,"id":131},{"wins":[94,211],"losses":[],"uri":"17_141-013.jpg","killed":"","score":1128,"id":133},{"wins":[232,234],"losses":[],"uri":"venus_19-111-017.jpg","killed":"","score":1105.4333863049296,"id":137},{"wins":[66,228],"losses":[],"uri":"venus_18-120-016.jpg","killed":"","score":1128,"id":78},{"wins":[140],"losses":[87],"uri":"venus_16_149-030.jpg","killed":"","score":1000,"id":239},{"wins":[242,273],"losses":[],"uri":"17_140-016.jpg","killed":"","score":1105.4333863049296,"id":134},{"wins":[],"losses":[47,127],"uri":"17_144-009.jpg","killed":"","score":872,"id":142},{"wins":[229],"losses":[12],"uri":"venus_16_151-006.jpg","killed":"","score":977.4333863049296,"id":37},{"wins":[],"losses":[91,62],"uri":"venus_16_161-028.jpg","killed":"","score":872,"id":196},{"wins":[240],"losses":[71],"uri":"venus_16_147-001.jpg","killed":"","score":977.4333863049296,"id":183},{"wins":[],"losses":[172,247],"uri":"venus_16_143-004.jpg","killed":"","score":872,"id":108},{"wins":[227],"losses":[10],"uri":"venus_16_154-010.jpg","killed":"","score":1000,"id":219},{"wins":[164],"losses":[8],"uri":"venus_12_40-003.jpg","killed":"","score":977.4333863049296,"id":149},{"wins":[8],"losses":[57],"uri":"venus_19-096-010.jpg","killed":"","score":1000,"id":34},{"wins":[226,222],"losses":[],"uri":"venus_16_149-018.jpg","killed":"","score":1128,"id":238},{"wins":[110],"losses":[277],"uri":"venus_16_150-026.jpg","killed":"","score":1000,"id":246},{"wins":[243,92],"losses":[],"uri":"venus_16_146-016.jpg","killed":"","score":1105.4333863049296,"id":152},{"wins":[],"losses":[174,134],"uri":"17_135-002.jpg","killed":"","score":894.5666136950704,"id":273},{"wins":[84,185],"losses":[],"uri":"17_137-003.jpg","killed":"","score":1128,"id":180},{"wins":[104],"losses":[281],"uri":"venus_19-107-001.jpg","killed":"","score":1000,"id":214},{"wins":[],"losses":[173,181],"uri":"venus_19-106-014.jpg","killed":"","score":872,"id":283},{"wins":[274,90],"losses":[],"uri":"17_128-013.jpg","killed":"","score":1128,"id":27},{"wins":[283],"losses":[69],"uri":"venus_16_146-028.jpg","killed":"","score":1000,"id":181},{"wins":[],"losses":[70,35],"uri":"venus-15_106-019.jpg","killed":"","score":872,"id":102},{"wins":[161,253],"losses":[],"uri":"venus_18-121-012.jpg","killed":"","score":1128,"id":82},{"wins":[],"losses":[134,176],"uri":"venus_16_144-006.jpg","killed":"","score":894.5666136950704,"id":242},{"wins":[75],"losses":[79],"uri":"17_118-009.jpg","killed":"","score":1000,"id":77},{"wins":[263,274],"losses":[],"uri":"17_127-024.jpg","killed":"","score":1105.4333863049296,"id":151},{"wins":[163,106],"losses":[],"uri":"venus_19-103-017.jpg","killed":"","score":1128,"id":21},{"wins":[],"losses":[32,214],"uri":"venus_16_143-011.jpg","killed":"","score":872,"id":104},{"wins":[261],"losses":[201],"uri":"17_120-004.jpg","killed":"","score":1000,"id":53},{"wins":[],"losses":[107,7],"uri":"venus_18-118-002.jpg","killed":"","score":894.5666136950704,"id":236},{"wins":[71],"losses":[276],"uri":"venus_18-114-018.jpg","killed":"","score":1000,"id":233},{"wins":[],"losses":[123,116],"uri":"17_139-017.jpg","killed":"","score":872,"id":22},{"wins":[249,50],"losses":[],"uri":"venus_19-101-007.jpg","killed":"","score":1128,"id":89},{"wins":[265,53],"losses":[],"uri":"17_132-021.jpg","killed":"","score":1128,"id":201},{"wins":[206],"losses":[21],"uri":"venus_19-100-023.jpg","killed":"","score":1000,"id":163},{"wins":[],"losses":[252,207],"uri":"venus_16_156-031.jpg","killed":"","score":894.5666136950704,"id":114},{"wins":[],"losses":[152,6],"uri":"venus_18-110-011.jpg","killed":"","score":894.5666136950704,"id":243},{"wins":[33,138],"losses":[],"uri":"venus_16_164-017.jpg","killed":"","score":1128,"id":109},{"wins":[257,45],"losses":[],"uri":"venus_19-110-025.jpg","killed":"","score":1128,"id":188},{"wins":[],"losses":[211,212],"uri":"venus-15_104-010.jpg","killed":"","score":894.5666136950704,"id":272},{"wins":[204,75],"losses":[],"uri":"venus_18-109-004.jpg","killed":"","score":1105.4333863049296,"id":213},{"wins":[22,143],"losses":[],"uri":"venus_19-099-008.jpg","killed":"","score":1105.4333863049296,"id":123},{"wins":[214],"losses":[174],"uri":"venus_18-122-021.jpg","killed":"","score":1000,"id":281},{"wins":[],"losses":[192,1],"uri":"venus_14_99-007-fussel.jpg","killed":"","score":872,"id":26},{"wins":[120],"losses":[11],"uri":"venus_16_164-019.jpg","killed":"","score":977.4333863049296,"id":199},{"wins":[],"losses":[89,217],"uri":"venus_18-119-016.jpg","killed":"","score":894.5666136950704,"id":249},{"wins":[66],"losses":[165],"uri":"venus_19-112-013.jpg","killed":"","score":1000,"id":31},{"wins":[221],"losses":[29],"uri":"venus_18-126-011.jpg","killed":"","score":1000,"id":218},{"wins":[],"losses":[45,173],"uri":"venus_16_143-009.jpg","killed":"","score":894.5666136950704,"id":186},{"wins":[0],"losses":[10],"uri":"venus_19-113-014.jpg","killed":"","score":1022.5666136950704,"id":4},{"wins":[95,103],"losses":[],"uri":"17_138-015.jpg","killed":"","score":1105.4333863049296,"id":65},{"wins":[95],"losses":[74],"uri":"venus_19-122-017.jpg","killed":"","score":1000,"id":167},{"wins":[],"losses":[119,15],"uri":"venus_16_153-028.jpg","killed":"","score":872,"id":121},{"wins":[],"losses":[207,170],"uri":"venus_16_161-022.jpg","killed":"","score":894.5666136950704,"id":115},{"wins":[],"losses":[7,14],"uri":"venus_14_96-002-fussel.jpg","killed":"","score":894.5666136950704,"id":54},{"wins":[140],"losses":[53],"uri":"venus_18-119-017.jpg","killed":"","score":1000,"id":261},{"wins":[240],"losses":[122],"uri":"17_130-011.jpg","killed":"","score":1000,"id":36},{"wins":[49],"losses":[222],"uri":"venus_16_164-002.jpg","killed":"","score":1000,"id":99},{"wins":[],"losses":[109,3],"uri":"17_131-014.jpg","killed":"","score":894.5666136950704,"id":33},{"wins":[],"losses":[219,110],"uri":"venus_19-112-019.jpg","killed":"","score":872,"id":227},{"wins":[],"losses":[212,65],"uri":"venus_14_95-016-fussel.jpg","killed":"","score":894.5666136950704,"id":103},{"wins":[11,94],"losses":[],"uri":"venus_16_147-005.jpg","killed":"","score":1105.4333863049296,"id":177},{"wins":[],"losses":[245,172],"uri":"venus_16_161-008.jpg","killed":"","score":894.5666136950704,"id":146},{"wins":[114,84],"losses":[],"uri":"venus_16_144-002.jpg","killed":"","score":1105.4333863049296,"id":252},{"wins":[99],"losses":[238],"uri":"17_129-020.jpg","killed":"","score":1000,"id":222},{"wins":[187],"losses":[14],"uri":"venus_16_146-027.jpg","killed":"","score":1000,"id":150},{"wins":[86,254],"losses":[],"uri":"venus_16_164-021.jpg","killed":"","score":1105.4333863049296,"id":160},{"wins":[],"losses":[77,213],"uri":"venus_16_147-032.jpg","killed":"","score":894.5666136950704,"id":75},{"wins":[],"losses":[90,105],"uri":"17_138-016.jpg","killed":"","score":872,"id":51},{"wins":[115,114],"losses":[],"uri":"venus_19-109-019.jpg","killed":"","score":1105.4333863049296,"id":207},{"wins":[199],"losses":[177],"uri":"17_128-004.jpg","killed":"","score":1022.5666136950704,"id":11},{"wins":[22],"losses":[41],"uri":"venus_19-111-014.jpg","killed":"","score":1000,"id":116},{"wins":[102],"losses":[184],"uri":"venus_19-121-024.jpg","killed":"","score":1000,"id":35},{"wins":[],"losses":[282,41],"uri":"venus_16_143-006.jpg","killed":"","score":894.5666136950704,"id":81},{"wins":[235],"losses":[55],"uri":"venus_18-110-010.jpg","killed":"","score":1000,"id":237},{"wins":[279,210],"losses":[],"uri":"venus_18-107-009.jpg","killed":"","score":1105.4333863049296,"id":202},{"wins":[],"losses":[68,101],"uri":"venus-15_106-009.jpg","killed":"","score":872,"id":126},{"wins":[],"losses":[218,52],"uri":"17_134-003.jpg","killed":"","score":894.5666136950704,"id":221},{"wins":[83],"losses":[97],"uri":"venus_19-119-012.jpg","killed":"","score":1022.5666136950704,"id":118},{"wins":[223],"losses":[124],"uri":"venus_16_144-009.jpg","killed":"","score":1022.5666136950704,"id":64},{"wins":[],"losses":[57,42],"uri":"venus_16_154-009.jpg","killed":"","score":872,"id":63},{"wins":[],"losses":[278,153],"uri":"venus-15_108-008.jpg","killed":"","score":894.5666136950704,"id":264},{"wins":[],"losses":[156,163],"uri":"17_144-014.jpg","killed":"","score":872,"id":206},{"wins":[25],"losses":[158],"uri":"venus_16_151-017.jpg","killed":"","score":1000,"id":18},{"wins":[247],"losses":[82],"uri":"17_135-001.jpg","killed":"","score":1000,"id":253},{"wins":[105,192],"losses":[],"uri":"venus_16_155-024.jpg","killed":"","score":1128,"id":60},{"wins":[167,279],"losses":[],"uri":"venus_16_161-018.jpg","killed":"","score":1105.4333863049296,"id":74},{"wins":[244],"losses":[67],"uri":"venus_16_148-027.jpg","killed":"","score":1000,"id":275},{"wins":[203],"losses":[220],"uri":"17_136-001.jpg","killed":"","score":1000,"id":195},{"wins":[64,72],"losses":[],"uri":"venus_19-108-002.jpg","killed":"","score":1105.4333863049296,"id":124},{"wins":[108,146],"losses":[],"uri":"venus_19-105-005.jpg","killed":"","score":1105.4333863049296,"id":172},{"wins":[40],"losses":[78],"uri":"venus_14_97-015-fussel.jpg","killed":"","score":1000,"id":228},{"wins":[],"losses":[27,151],"uri":"17_138-009.jpg","killed":"","score":894.5666136950704,"id":274},{"wins":[26],"losses":[223],"uri":"venus_18-115-003.jpg","killed":"","score":1000,"id":1},{"wins":[],"losses":[239,261],"uri":"venus_14_97-005-fussel.jpg","killed":"","score":872,"id":140},{"wins":[],"losses":[50,179],"uri":"venus-15_103-001.jpg","killed":"","score":894.5666136950704,"id":113},{"wins":[],"losses":[44,230],"uri":"venus_18-111-024.jpg","killed":"","score":894.5666136950704,"id":46},{"wins":[143,113],"losses":[],"uri":"17_127-017.jpg","killed":"","score":1105.4333863049296,"id":179},{"wins":[154,229],"losses":[],"uri":"17_132-015.jpg","killed":"","score":1105.4333863049296,"id":141},{"wins":[164],"losses":[23],"uri":"venus_18-120-004.jpg","killed":"","score":1000,"id":117},{"wins":[196,270],"losses":[],"uri":"17_141-001.jpg","killed":"","score":1128,"id":91},{"wins":[],"losses":[73,107],"uri":"venus_16_148-030.jpg","killed":"","score":894.5666136950704,"id":255},{"wins":[131,258],"losses":[],"uri":"venus_16_163-022.jpg","killed":"","score":1105.4333863049296,"id":5},{"wins":[248,18],"losses":[],"uri":"venus_16_143-027.jpg","killed":"","score":1128,"id":158},{"wins":[],"losses":[78,31],"uri":"17_128-001.jpg","killed":"","score":872,"id":66},{"wins":[],"losses":[133,177],"uri":"venus-15_103-002.jpg","killed":"","score":894.5666136950704,"id":94},{"wins":[210,88],"losses":[],"uri":"venus_16_149-032.jpg","killed":"","score":1128,"id":225},{"wins":[121],"losses":[58],"uri":"venus_19-106-018.jpg","killed":"","score":1000,"id":15},{"wins":[116,81],"losses":[],"uri":"17_128-003.jpg","killed":"","score":1105.4333863049296,"id":41},{"wins":[245],"losses":[16],"uri":"venus_16_153-018.jpg","killed":"","score":1022.5666136950704,"id":169},{"wins":[231,178],"losses":[],"uri":"17_127-018.jpg","killed":"","score":1105.4333863049296,"id":148},{"wins":[96],"losses":[139],"uri":"venus_19-104-015.jpg","killed":"","score":1000,"id":168},{"wins":[101,189],"losses":[],"uri":"venus_16_157-023.jpg","killed":"","score":1128,"id":136},{"wins":[162],"losses":[20],"uri":"venus_18-109-002.jpg","killed":"","score":1000,"id":250},{"wins":[283,186],"losses":[],"uri":"venus_19-115-005.jpg","killed":"","score":1105.4333863049296,"id":173},{"wins":[128,38],"losses":[],"uri":"venus_18-107-005.jpg","killed":"","score":1105.4333863049296,"id":80},{"wins":[190,33],"losses":[],"uri":"17_138-011.jpg","killed":"","score":1105.4333863049296,"id":3},{"wins":[126,161],"losses":[],"uri":"venus_16_151-004.jpg","killed":"","score":1105.4333863049296,"id":68},{"wins":[72],"losses":[265],"uri":"venus-15_107-008.jpg","killed":"","score":977.4333863049296,"id":100},{"wins":[198],"losses":[165],"uri":"venus_19-117-004.jpg","killed":"","score":1000,"id":269},{"wins":[2,154],"losses":[],"uri":"venus_16_164-008.jpg","killed":"","score":1105.4333863049296,"id":155},{"wins":[215,156],"losses":[],"uri":"17_140-013.jpg","killed":"","score":1128,"id":111},{"wins":[260],"losses":[215],"uri":"venus_16_154-033.jpg","killed":"","score":977.4333863049296,"id":28},{"wins":[],"losses":[183,36],"uri":"venus_16_145-016.jpg","killed":"","score":872,"id":240},{"wins":[43],"losses":[106],"uri":"venus_19-100-027.jpg","killed":"","score":1000,"id":194},{"wins":[169,40],"losses":[],"uri":"17_131-011.jpg","killed":"","score":1105.4333863049296,"id":16},{"wins":[119],"losses":[79],"uri":"17_137-005.jpg","killed":"","score":1022.5666136950704,"id":209},{"wins":[25],"losses":[137],"uri":"venus_16_150-027.jpg","killed":"","score":1000,"id":232},{"wins":[],"losses":[158,24],"uri":"venus_14_96-018-fussel.jpg","killed":"","score":872,"id":248},{"wins":[193],"losses":[160],"uri":"venus_18-120-003.jpg","killed":"","score":1000,"id":86},{"wins":[187],"losses":[231],"uri":"venus_18-109-003.jpg","killed":"","score":977.4333863049296,"id":262},{"wins":[147,162],"losses":[],"uri":"17_141-018.jpg","killed":"","score":1105.4333863049296,"id":197},{"wins":[254],"losses":[260],"uri":"venus_16_151-018.jpg","killed":"","score":977.4333863049296,"id":271},{"wins":[],"losses":[3,224],"uri":"venus_16_146-013.jpg","killed":"","score":894.5666136950704,"id":190},{"wins":[241,243],"losses":[],"uri":"venus_16_155-021.jpg","killed":"","score":1105.4333863049296,"id":6},{"wins":[129],"losses":[109],"uri":"venus_16_164-010.jpg","killed":"","score":1000,"id":138},{"wins":[],"losses":[270,237],"uri":"venus_18-118-016.jpg","killed":"","score":872,"id":235},{"wins":[],"losses":[176,48],"uri":"venus_19-116-017.jpg","killed":"","score":894.5666136950704,"id":266},{"wins":[9],"losses":[136],"uri":"17_137-012.jpg","killed":"","score":1000,"id":189},{"wins":[],"losses":[202,74],"uri":"venus_18-126-001.jpg","killed":"","score":894.5666136950704,"id":279},{"wins":[],"losses":[88,19],"uri":"17_144-013.jpg","killed":"","score":894.5666136950704,"id":166},{"wins":[],"losses":[157,168],"uri":"17_127-023.jpg","killed":"","score":872,"id":96},{"wins":[103,272],"losses":[],"uri":"venus_19-106-010.jpg","killed":"","score":1105.4333863049296,"id":212},{"wins":[278],"losses":[153],"uri":"venus_19-115-011.jpg","killed":"","score":1022.5666136950704,"id":171},{"wins":[76,246],"losses":[],"uri":"17_139-025.jpg","killed":"","score":1128,"id":277},{"wins":[28],"losses":[111],"uri":"venus_18-110-013.jpg","killed":"","score":1022.5666136950704,"id":215},{"wins":[],"losses":[61,152],"uri":"venus_16_161-031.jpg","killed":"","score":894.5666136950704,"id":92},{"wins":[186],"losses":[188],"uri":"venus_18-111-025.jpg","killed":"","score":1000,"id":45},{"wins":[],"losses":[138,216],"uri":"venus_19-098-019.jpg","killed":"","score":872,"id":129},{"wins":[178],"losses":[85],"uri":"venus_16_150-009.jpg","killed":"","score":1000,"id":268},{"wins":[],"losses":[82,68],"uri":"17_141-020.jpg","killed":"","score":894.5666136950704,"id":161},{"wins":[205],"losses":[55],"uri":"venus_16_164-016.jpg","killed":"","score":1000,"id":98},{"wins":[],"losses":[276,80],"uri":"venus-15_109-011.jpg","killed":"","score":894.5666136950704,"id":38},{"wins":[128],"losses":[188],"uri":"venus_18-111-004.jpg","killed":"","score":1000,"id":257},{"wins":[117],"losses":[58],"uri":"venus_16_148-015.jpg","killed":"","score":1000,"id":23},{"wins":[],"losses":[200,205],"uri":"venus_18-115-002.jpg","killed":"","score":872,"id":13},{"wins":[227],"losses":[246],"uri":"venus_16_161-032.jpg","killed":"","score":1000,"id":110},{"wins":[],"losses":[180,252],"uri":"venus_14_95-007-fussel.jpg","killed":"","score":894.5666136950704,"id":84},{"wins":[130],"losses":[230],"uri":"venus-15_107-006.jpg","killed":"","score":1000,"id":208},{"wins":[],"losses":[225,202],"uri":"17_137-011.jpg","killed":"","score":894.5666136950704,"id":210},{"wins":[43,125],"losses":[],"uri":"17_127-022.jpg","killed":"","score":1128,"id":112},{"wins":[38,233],"losses":[],"uri":"venus_16_163-007.jpg","killed":"","score":1128,"id":276},{"wins":[127,218],"losses":[],"uri":"venus_16_162-025.jpg","killed":"","score":1128,"id":29},{"wins":[35,198],"losses":[],"uri":"venus_16_152-030.jpg","killed":"","score":1105.4333863049296,"id":184},{"wins":[4,219],"losses":[],"uri":"17_143-013.jpg","killed":"","score":1128,"id":10},{"wins":[146],"losses":[169],"uri":"venus-15_104-003.jpg","killed":"","score":977.4333863049296,"id":245},{"wins":[49],"losses":[4],"uri":"venus-15_109-003.jpg","killed":"","score":977.4333863049296,"id":0},{"wins":[135],"losses":[256],"uri":"17_142-025.jpg","killed":"","score":1000,"id":259},{"wins":[235],"losses":[91],"uri":"venus_16_151-024.jpg","killed":"","score":1000,"id":270},{"wins":[],"losses":[80,257],"uri":"venus_16_143-001.jpg","killed":"","score":872,"id":128},{"wins":[],"losses":[159,5],"uri":"venus_16_144-017.jpg","killed":"","score":894.5666136950704,"id":258},{"wins":[203],"losses":[180],"uri":"venus-15_107-004.jpg","killed":"","score":1000,"id":185},{"wins":[63,34],"losses":[],"uri":"venus_19-117-019.jpg","killed":"","score":1128,"id":57},{"wins":[113],"losses":[89],"uri":"venus_18-110-009.jpg","killed":"","score":1000,"id":50},{"wins":[63],"losses":[19],"uri":"17_125-008.jpg","killed":"","score":1000,"id":42},{"wins":[],"losses":[155,220],"uri":"venus-15_111-011.jpg","killed":"","score":894.5666136950704,"id":2},{"wins":[39,139],"losses":[],"uri":"venus_16_164-012.jpg","killed":"","score":1128,"id":132},{"wins":[],"losses":[179,123],"uri":"venus_16_164-005.jpg","killed":"","score":894.5666136950704,"id":143},{"wins":[],"losses":[100,124],"uri":"venus_19-097-017.jpg","killed":"","score":894.5666136950704,"id":72},{"wins":[258],"losses":[17],"uri":"17_132-019.jpg","killed":"","score":977.4333863049296,"id":159},{"wins":[62],"losses":[118],"uri":"venus_16_143-013.jpg","killed":"","score":977.4333863049296,"id":83},{"wins":[208,46],"losses":[],"uri":"venus_19-120-011.jpg","killed":"","score":1105.4333863049296,"id":230},{"wins":[44],"losses":[145],"uri":"17_131-017.jpg","killed":"","score":1022.5666136950704,"id":56},{"wins":[168],"losses":[132],"uri":"17_132-014.jpg","killed":"","score":1000,"id":139},{"wins":[280],"losses":[32],"uri":"venus_18-122-008.jpg","killed":"","score":1000,"id":267},{"wins":[],"losses":[87,47],"uri":"venus_16_155-019.jpg","killed":"","score":894.5666136950704,"id":59},{"wins":[12,275],"losses":[],"uri":"venus_19-112-015.jpg","killed":"","score":1128,"id":67},{"wins":[273,281],"losses":[],"uri":"venus-15_106-011.jpg","killed":"","score":1128,"id":174},{"wins":[147],"losses":[189],"uri":"venus_19-103-001.jpg","killed":"","score":1000,"id":9},{"wins":[175],"losses":[213],"uri":"venus_19-099-017.jpg","killed":"","score":1000,"id":204},{"wins":[],"losses":[262,150],"uri":"venus-15_112-008.jpg","killed":"","score":872,"id":187},{"wins":[],"losses":[269,184],"uri":"venus_14_98-003-fussel.jpg","killed":"","score":894.5666136950704,"id":198},{"wins":[31,269],"losses":[],"uri":"venus_16_152-009.jpg","killed":"","score":1128,"id":165},{"wins":[],"losses":[0,99],"uri":"venus-15_111-016.jpg","killed":"","score":872,"id":49},{"wins":[],"losses":[48,204],"uri":"venus_14_97-006-fussel.jpg","killed":"","score":872,"id":175},{"wins":[102,182],"losses":[],"uri":"venus_16_150-001.jpg","killed":"","score":1105.4333863049296,"id":70},{"wins":[],"losses":[197,9],"uri":"venus_19-100-007.jpg","killed":"","score":872,"id":147},{"wins":[135],"losses":[112],"uri":"venus-15_106-021.jpg","killed":"","score":1000,"id":125},{"wins":[],"losses":[199,251],"uri":"venus_16_143-014.jpg","killed":"","score":872,"id":120},{"wins":[],"losses":[228,16],"uri":"17_142-005.jpg","killed":"","score":894.5666136950704,"id":40},{"wins":[36,191],"losses":[],"uri":"venus_19-105-008.jpg","killed":"","score":1128,"id":122},{"wins":[54,236],"losses":[],"uri":"venus_16_158-016.jpg","killed":"","score":1105.4333863049296,"id":7},{"wins":[],"losses":[132,76],"uri":"venus_19-112-003.jpg","killed":"","score":872,"id":39},{"wins":[271],"losses":[28],"uri":"venus_16_151-032.jpg","killed":"","score":1022.5666136950704,"id":260},{"wins":[],"losses":[170,208],"uri":"venus_19-109-007.jpg","killed":"","score":872,"id":130},{"wins":[237,98],"losses":[],"uri":"venus-15_115-008.jpg","killed":"","score":1128,"id":55},{"wins":[],"losses":[271,160],"uri":"venus_18-127-012.jpg","killed":"","score":894.5666136950704,"id":254},{"wins":[144],"losses":[122],"uri":"17_127-004.jpg","killed":"","score":1000,"id":191},{"wins":[236,255],"losses":[],"uri":"venus_18-121-005.jpg","killed":"","score":1105.4333863049296,"id":107},{"wins":[],"losses":[65,167],"uri":"17_127-009.jpg","killed":"","score":872,"id":95},{"wins":[193],"losses":[256],"uri":"venus-15_111-013.jpg","killed":"","score":1000,"id":30},{"wins":[255,61],"losses":[],"uri":"17_127-020.jpg","killed":"","score":1128,"id":73},{"wins":[],"losses":[185,195],"uri":"venus_14_103-014-fussel.jpg","killed":"","score":872,"id":203},{"wins":[181,97],"losses":[],"uri":"venus_16_150-029.jpg","killed":"","score":1128,"id":69},{"wins":[],"losses":[125,259],"uri":"venus_16_161-009.jpg","killed":"","score":872,"id":135},{"wins":[129],"losses":[20],"uri":"17_138-024.jpg","killed":"","score":1000,"id":216},{"wins":[56,282],"losses":[],"uri":"venus_16_157-022.jpg","killed":"","score":1128,"id":145},{"wins":[96,280],"losses":[],"uri":"17_132-018.jpg","killed":"","score":1105.4333863049296,"id":157},{"wins":[118],"losses":[69],"uri":"venus_16_147-025.jpg","killed":"","score":1000,"id":97},{"wins":[216,250],"losses":[],"uri":"venus_19-113-003.jpg","killed":"","score":1128,"id":20},{"wins":[17,221],"losses":[],"uri":"17_142-010.jpg","killed":"","score":1105.4333863049296,"id":52},{"wins":[266,242],"losses":[],"uri":"venus_19-098-015.jpg","killed":"","score":1105.4333863049296,"id":176}],"killed":[],"rounds":[{"percent":"0"},{"percent":"33"}],"currentState":[{"currentPhoto":0,"correctAnswer":0}],"meta":[{"baseUrl":"photos/venuscloseups/"}]}'

var json = JSON.parse(jsonfile);

//var currentPhoto = -2;
//var correctAnswer = 0;
var currentPhoto = json.currentState[0].currentPhoto;
var correctAnswer = json.currentState[0].correctAnswer;
var baseUrl = json.meta[0].baseUrl;

var points = $.map(json.photos, function(value, index){
        return [value];
    });


var killRound = 3;
var killPhotos = 10;


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

   
   json.killed.sort(function(a, b){
    var a1= a.score, b1= b.score;
    if(a1== b1) return 0;
    return a1< b1? 1: -1;
  });
   
   // MAKE KILLED-TABLE
   for (var i = 0; i < json.killed.length; i++) {
    $("#completeTable table").append("<tr class=killed><td>" + (i+points.length+1) + ".</td><td>" + json.killed[i].uri + "</td><td>" + json.killed[i].wins.length + "</td><td>" + json.killed[i].losses.length + "</td><td>" + json.killed[i].score.toFixed(0) + "</td></tr>");
   }
   
  
     
    
 
}

function makeRoundStats() {

  $("#roundStats table").empty();
  for (var i = 0; i < json.rounds.length; i++) {
    $("#roundStats table").append("<tr><td>ROUND " + (i) + "</td><td>" + json.rounds[i].percent + "%</td></tr>");
  }

  percent = correctAnswer*100/(currentPhoto/2);

  $("#round").html("<table><tr><td>ROUND " + (json.rounds.length) + "</td><td>" + (currentPhoto/2) + "/" + (json.photos.length/2) + "</td></tr></table>");
  
  if (isNaN(percent)) {
    $("#roundAccuracy").text("0%");
  } else {
    $("#roundAccuracy").text(percent.toFixed(0) + "%");
  }

}

function drawScreen() {

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

}

function updatePhotos() {

  // CHECK LENGTH
  if (currentPhoto == (json.photos.length-2)) {

    currentPhoto = 0;
    correctAnswer = 0;
    json.currentState[0].currentPhoto = 0;
    json.currentState[0].correctAnswer = 0;
    
    json.rounds.push({ percent: percent.toFixed(0) });
    
    
    // KILL LAST X PHOTOS (IF EIN VIELFACHES VON KILLROUND)
    if ((json.rounds.length-1 != 0) && ((json.rounds.length-1) % killRound == 0)) {
      
      console.log("KILL EM!");
      for (var i = (points.length-killPhotos); i < points.length; i++) {
        // KILLED-FLAG AUF DIE AKTUELLE RUNDE SETZEN
        json.photos[json.photos.findIndex(el => el.id === points[i].id)].killed = json.rounds.length-1;
        
        // IN KILLED KOPIEREN UND AUS PHOTOS LOESCHEN
        json.killed.push(json.photos[json.photos.findIndex(el => el.id === points[i].id)]);
        json.photos.splice(json.photos.findIndex(el => el.id === points[i].id), 1);

      }
      
      // DIE LETZTEN BEIDEN EINTRÄGE AUS POINTS LOESCHEN
      points.splice(-killPhotos, killPhotos);      
      
      
    }
    
    $("#message").text("ROUND " + json.rounds.length);
    $("#message").addClass("on");
    setTimeout(function(){ $("#message").removeClass("on"); }, 1000);
    
    
    console.log(percent.toFixed(0) + "%")
    console.log("NEW SHUFFLE")
    
    shuffle(json.photos);
    
  } else { 
    currentPhoto += 2;
    json.currentState[0].currentPhoto += 2;
  }
 
  drawScreen();
 
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
    json.currentState[0].correctAnswer++
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
    json.currentState[0].correctAnswer++
  }  
    
  updatePhotos();

}



function showRanking() {

  var rankingArray = json.photos.concat(json.killed);
  
  rankingArray.sort(function(a, b){
    var a1= a.score, b1= b.score;
    if(a1== b1) return 0;
    return a1< b1? 1: -1;
  });

  $("#grid").empty();
  $("#canvas").show();

  for (var i = 0; i < rankingArray.length; i++) {
  
    if (i == 0) {
      $("#grid").append("<h2>&starf;&starf;&starf;&starf;</h2>");
    }
  
    if (i == Math.floor(rankingArray.length*0.25)) {
      $("#grid").append("<h2>&starf;&starf;&starf;</h2>");
    }
    
    if (i == Math.floor(rankingArray.length*0.50)) {
      $("#grid").append("<h2>&starf;&starf;</h2>");
    }
    
    if (i == Math.floor(rankingArray.length*0.75)) {
      $("#grid").append("<h2>&starf;</h2>");
    }   
    
    if (rankingArray[i].killed > 0) {  
      $("#grid").append("<div class=\"gridItem off\"><div class=\"glass\">" + rankingArray[i].killed + "</div><img src=" + baseUrl + "" + rankingArray[i].uri + "></div>");
    } else {
      $("#grid").append("<div class=\"gridItem\"><img src=" + baseUrl + "" + rankingArray[i].uri + "></div>");
    }
    

  
  }

}

function showKilled() {

  var killedArray = json.killed;
  
  killedArray.sort(function(a, b){
    var a1= a.score, b1= b.score;
    if(a1== b1) return 0;
    return a1< b1? 1: -1;
  });

  $("#grid").empty();
  $("#canvas").show();

  for (var i = 0; i < killedArray.length; i++) {
    $("#grid").append("<div class=\"gridItem off\"><div class=\"glass\">" + killedArray[i].killed + "</div><img src=" + baseUrl + "" + killedArray[i].uri + "></div>");  
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

$("#killed").click(function() {

  showKilled();
  
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
if (currentPhoto == 0) { shuffle(json.photos); }
drawScreen();
makeTable();
makeRoundStats();


