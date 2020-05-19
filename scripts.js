// DETAILANSICHT PRO BILD GEGEN WELCHE ES GEWONNEN ODER VERLOREN HAT

// NACH JEDEM DURCHLAUF MUSS IRGENDWAS AUFBLINKEN DAMIT MAN DAS WEISS
// EINZELFOTO-ANSICH


// FUNKTION DAS MAN DIE SCHLECHTESTEN FOTOS NACHEINANDER AUS DEM ARRAY KILLT (ODER EINFACH NUR N FLAG SETZT)
// FLAG IM STYLE VON "killed: 3" (BZW. DIE RUNDENZAHL IN DER DIE RAUSGEWORFEN WURDE)
// VIELLEICHT IST DIE IDEE AUCH BESSER JEDE 3 RUNDEN DIE LETZTEN 6 (ODER SO) FOTOS AUS DEM ARRAY ZU NEHMEN

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
'[{"wins": [], "losses": [], "uri": "xkopp-venus-15_113-005.jpg", "killed": "", "score": 1000, "id": 0}, {"wins": [], "losses": [], "uri": "venus_18-122-004.jpg", "killed": "", "score": 1000, "id": 1}, {"wins": [], "losses": [], "uri": "venus_18-123-001.jpg", "killed": "", "score": 1000, "id": 2}, {"wins": [], "losses": [], "uri": "venus_16_162-027.jpg", "killed": "", "score": 1000, "id": 3}, {"wins": [], "losses": [], "uri": "17_138-005.jpg", "killed": "", "score": 1000, "id": 4}, {"wins": [], "losses": [], "uri": "venus_16_145-020.jpg", "killed": "", "score": 1000, "id": 5}, {"wins": [], "losses": [], "uri": "17_139-001.jpg", "killed": "", "score": 1000, "id": 6}, {"wins": [], "losses": [], "uri": "17_124-022.jpg", "killed": "", "score": 1000, "id": 7}, {"wins": [], "losses": [], "uri": "17_129-001.jpg", "killed": "", "score": 1000, "id": 8}, {"wins": [], "losses": [], "uri": "venus_19-113-015.jpg", "killed": "", "score": 1000, "id": 9}, {"wins": [], "losses": [], "uri": "venus_19-113-001.jpg", "killed": "", "score": 1000, "id": 10}, {"wins": [], "losses": [], "uri": "17_138-010.jpg", "killed": "", "score": 1000, "id": 11}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_112-001.jpg", "killed": "", "score": 1000, "id": 12}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_113-010.jpg", "killed": "", "score": 1000, "id": 13}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_113-006.jpg", "killed": "", "score": 1000, "id": 14}, {"wins": [], "losses": [], "uri": "venus_18-111-008.jpg", "killed": "", "score": 1000, "id": 15}, {"wins": [], "losses": [], "uri": "17_129-016.jpg", "killed": "", "score": 1000, "id": 16}, {"wins": [], "losses": [], "uri": "17_138-007.jpg", "killed": "", "score": 1000, "id": 17}, {"wins": [], "losses": [], "uri": "venus_18-123-003.jpg", "killed": "", "score": 1000, "id": 18}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_113-007.jpg", "killed": "", "score": 1000, "id": 19}, {"wins": [], "losses": [], "uri": "venus_19-097-011.jpg", "killed": "", "score": 1000, "id": 20}, {"wins": [], "losses": [], "uri": "venus_18-123-007.jpg", "killed": "", "score": 1000, "id": 21}, {"wins": [], "losses": [], "uri": "17_129-006.jpg", "killed": "", "score": 1000, "id": 23}, {"wins": [], "losses": [], "uri": "17_139-012.jpg", "killed": "", "score": 1000, "id": 24}, {"wins": [], "losses": [], "uri": "17_139-013.jpg", "killed": "", "score": 1000, "id": 25}, {"wins": [], "losses": [], "uri": "venus_16_144-022.jpg", "killed": "", "score": 1000, "id": 26}, {"wins": [], "losses": [], "uri": "venus_19-102-002.jpg", "killed": "", "score": 1000, "id": 27}, {"wins": [], "losses": [], "uri": "venus_18-122-001.jpg", "killed": "", "score": 1000, "id": 28}, {"wins": [], "losses": [], "uri": "venus_16_145-019.jpg", "killed": "", "score": 1000, "id": 29}, {"wins": [], "losses": [], "uri": "venus_18-122-014.jpg", "killed": "", "score": 1000, "id": 30}, {"wins": [], "losses": [], "uri": "venus_16_161-024.jpg", "killed": "", "score": 1000, "id": 31}, {"wins": [], "losses": [], "uri": "venus_19-111-006.jpg", "killed": "", "score": 1000, "id": 32}, {"wins": [], "losses": [], "uri": "venus_16_153-012.jpg", "killed": "", "score": 1000, "id": 33}, {"wins": [], "losses": [], "uri": "venus_18-121-013.jpg", "killed": "", "score": 1000, "id": 34}, {"wins": [], "losses": [], "uri": "venus_19-108-010.jpg", "killed": "", "score": 1000, "id": 35}, {"wins": [], "losses": [], "uri": "venus_19-119-001.jpg", "killed": "", "score": 1000, "id": 36}, {"wins": [], "losses": [], "uri": "venus_16_161-025.jpg", "killed": "", "score": 1000, "id": 37}, {"wins": [], "losses": [], "uri": "venus_19-100-002.jpg", "killed": "", "score": 1000, "id": 38}, {"wins": [], "losses": [], "uri": "17_137-023.jpg", "killed": "", "score": 1000, "id": 39}, {"wins": [], "losses": [], "uri": "venus_19-100-028.jpg", "killed": "", "score": 1000, "id": 40}, {"wins": [], "losses": [], "uri": "venus_16_161-027.jpg", "killed": "", "score": 1000, "id": 41}, {"wins": [], "losses": [], "uri": "17_122-006.jpg", "killed": "", "score": 1000, "id": 42}, {"wins": [], "losses": [], "uri": "17_122-007.jpg", "killed": "", "score": 1000, "id": 43}, {"wins": [], "losses": [], "uri": "venus_19-119-016.jpg", "killed": "", "score": 1000, "id": 44}, {"wins": [], "losses": [], "uri": "venus_19-104-009.jpg", "killed": "", "score": 1000, "id": 45}, {"wins": [], "losses": [], "uri": "venus_19-114-009.jpg", "killed": "", "score": 1000, "id": 46}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_111-015.jpg", "killed": "", "score": 1000, "id": 47}, {"wins": [], "losses": [], "uri": "venus_16_146-021.jpg", "killed": "", "score": 1000, "id": 48}, {"wins": [], "losses": [], "uri": "venus_16_146-025.jpg", "killed": "", "score": 1000, "id": 49}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_109-017.jpg", "killed": "", "score": 1000, "id": 50}, {"wins": [], "losses": [], "uri": "venus_19-115-008.jpg", "killed": "", "score": 1000, "id": 51}, {"wins": [], "losses": [], "uri": "venus_19-115-009.jpg", "killed": "", "score": 1000, "id": 52}, {"wins": [], "losses": [], "uri": "venus_18-121-014.jpg", "killed": "", "score": 1000, "id": 53}, {"wins": [], "losses": [], "uri": "venus_18-120-011.jpg", "killed": "", "score": 1000, "id": 54}, {"wins": [], "losses": [], "uri": "venus_16_161-023.jpg", "killed": "", "score": 1000, "id": 55}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_109-016.jpg", "killed": "", "score": 1000, "id": 56}, {"wins": [], "losses": [], "uri": "venus_16_146-024.jpg", "killed": "", "score": 1000, "id": 57}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_109-014.jpg", "killed": "", "score": 1000, "id": 58}, {"wins": [], "losses": [], "uri": "venus_19-111-003.jpg", "killed": "", "score": 1000, "id": 59}, {"wins": [], "losses": [], "uri": "venus_16_152-006.jpg", "killed": "", "score": 1000, "id": 60}, {"wins": [], "losses": [], "uri": "venus_19-109-005.jpg", "killed": "", "score": 1000, "id": 61}, {"wins": [], "losses": [], "uri": "venus_16_153-003.jpg", "killed": "", "score": 1000, "id": 62}, {"wins": [], "losses": [], "uri": "venus_19-108-001.jpg", "killed": "", "score": 1000, "id": 63}, {"wins": [], "losses": [], "uri": "venus_16_152-013.jpg", "killed": "", "score": 1000, "id": 64}, {"wins": [], "losses": [], "uri": "venus_16_161-011.jpg", "killed": "", "score": 1000, "id": 65}, {"wins": [], "losses": [], "uri": "venus_19-122-014.jpg", "killed": "", "score": 1000, "id": 66}, {"wins": [], "losses": [], "uri": "17_119-011.jpg", "killed": "", "score": 1000, "id": 67}, {"wins": [], "losses": [], "uri": "venus_19-099-013.jpg", "killed": "", "score": 1000, "id": 68}, {"wins": [], "losses": [], "uri": "venus_19-098-002.jpg", "killed": "", "score": 1000, "id": 69}, {"wins": [], "losses": [], "uri": "venus_18-120-022.jpg", "killed": "", "score": 1000, "id": 70}, {"wins": [], "losses": [], "uri": "venus_16_161-010.jpg", "killed": "", "score": 1000, "id": 71}, {"wins": [], "losses": [], "uri": "venus_16_161-012.jpg", "killed": "", "score": 1000, "id": 72}, {"wins": [], "losses": [], "uri": "venus_16_161-006.jpg", "killed": "", "score": 1000, "id": 73}, {"wins": [], "losses": [], "uri": "venus_19-101-018.jpg", "killed": "", "score": 1000, "id": 74}, {"wins": [], "losses": [], "uri": "venus_19-104-001.jpg", "killed": "", "score": 1000, "id": 75}, {"wins": [], "losses": [], "uri": "venus_16_153-025.jpg", "killed": "", "score": 1000, "id": 76}, {"wins": [], "losses": [], "uri": "venus_16_152-020.jpg", "killed": "", "score": 1000, "id": 77}, {"wins": [], "losses": [], "uri": "17_123-023.jpg", "killed": "", "score": 1000, "id": 78}, {"wins": [], "losses": [], "uri": "venus_16_161-003.jpg", "killed": "", "score": 1000, "id": 79}, {"wins": [], "losses": [], "uri": "venus_19-114-010.jpg", "killed": "", "score": 1000, "id": 80}, {"wins": [], "losses": [], "uri": "venus_16_153-021.jpg", "killed": "", "score": 1000, "id": 81}, {"wins": [], "losses": [], "uri": "venus_18-121-021.jpg", "killed": "", "score": 1000, "id": 82}, {"wins": [], "losses": [], "uri": "venus_16_152-031.jpg", "killed": "", "score": 1000, "id": 83}, {"wins": [], "losses": [], "uri": "venus_19-111-020.jpg", "killed": "", "score": 1000, "id": 84}, {"wins": [], "losses": [], "uri": "venus_16_161-002.jpg", "killed": "", "score": 1000, "id": 85}, {"wins": [], "losses": [], "uri": "venus_16_161-016.jpg", "killed": "", "score": 1000, "id": 86}, {"wins": [], "losses": [], "uri": "venus_16_147-028.jpg", "killed": "", "score": 1000, "id": 87}, {"wins": [], "losses": [], "uri": "venus_19-114-007.jpg", "killed": "", "score": 1000, "id": 88}, {"wins": [], "losses": [], "uri": "venus_19-122-011.jpg", "killed": "", "score": 1000, "id": 89}, {"wins": [], "losses": [], "uri": "venus_19-105-002.jpg", "killed": "", "score": 1000, "id": 90}, {"wins": [], "losses": [], "uri": "venus_19-099-016.jpg", "killed": "", "score": 1000, "id": 91}, {"wins": [], "losses": [], "uri": "venus_19-104-012.jpg", "killed": "", "score": 1000, "id": 92}, {"wins": [], "losses": [], "uri": "venus_19-114-006.jpg", "killed": "", "score": 1000, "id": 93}, {"wins": [], "losses": [], "uri": "venus_16_152-026.jpg", "killed": "", "score": 1000, "id": 94}, {"wins": [], "losses": [], "uri": "venus_16_161-015.jpg", "killed": "", "score": 1000, "id": 95}, {"wins": [], "losses": [], "uri": "venus_16_146-012.jpg", "killed": "", "score": 1000, "id": 96}, {"wins": [], "losses": [], "uri": "venus_18-123-008.jpg", "killed": "", "score": 1000, "id": 97}, {"wins": [], "losses": [], "uri": "venus_16_144-010.jpg", "killed": "", "score": 1000, "id": 98}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_106-015.jpg", "killed": "", "score": 1000, "id": 99}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_113-019.jpg", "killed": "", "score": 1000, "id": 100}, {"wins": [], "losses": [], "uri": "17_131-026.jpg", "killed": "", "score": 1000, "id": 101}, {"wins": [], "losses": [], "uri": "venus_19-106-005.jpg", "killed": "", "score": 1000, "id": 102}, {"wins": [], "losses": [], "uri": "venus_19-116-011.jpg", "killed": "", "score": 1000, "id": 103}, {"wins": [], "losses": [], "uri": "venus_19-116-013.jpg", "killed": "", "score": 1000, "id": 104}, {"wins": [], "losses": [], "uri": "venus_18-119-013.jpg", "killed": "", "score": 1000, "id": 105}, {"wins": [], "losses": [], "uri": "venus_16_144-013.jpg", "killed": "", "score": 1000, "id": 106}, {"wins": [], "losses": [], "uri": "venus_16_149-024.jpg", "killed": "", "score": 1000, "id": 107}, {"wins": [], "losses": [], "uri": "17_129-023.jpg", "killed": "", "score": 1000, "id": 108}, {"wins": [], "losses": [], "uri": "venus_16_149-025.jpg", "killed": "", "score": 1000, "id": 109}, {"wins": [], "losses": [], "uri": "venus_19-121-001.jpg", "killed": "", "score": 1000, "id": 110}, {"wins": [], "losses": [], "uri": "venus_19-116-006.jpg", "killed": "", "score": 1000, "id": 111}, {"wins": [], "losses": [], "uri": "venus_16_154-002.jpg", "killed": "", "score": 1000, "id": 112}, {"wins": [], "losses": [], "uri": "venus_16_144-016.jpg", "killed": "", "score": 1000, "id": 113}, {"wins": [], "losses": [], "uri": "17_124-011.jpg", "killed": "", "score": 1000, "id": 114}, {"wins": [], "losses": [], "uri": "venus_16_145-012.jpg", "killed": "", "score": 1000, "id": 115}, {"wins": [], "losses": [], "uri": "xkopp-venus-15_107-003.jpg", "killed": "", "score": 1000, "id": 116}, {"wins": [], "losses": [], "uri": "venus_18-118-004.jpg", "killed": "", "score": 1000, "id": 117}, {"wins": [], "losses": [], "uri": "venus_16_144-029.jpg", "killed": "", "score": 1000, "id": 118}, {"wins": [], "losses": [], "uri": "venus_16_162-003.jpg", "killed": "", "score": 1000, "id": 119}, {"wins": [], "losses": [], "uri": "venus_16_162-002.jpg", "killed": "", "score": 1000, "id": 120}, {"wins": [], "losses": [], "uri": "17_138-008.jpg", "killed": "", "score": 1000, "id": 121}, {"wins": [], "losses": [], "uri": "venus_16_151-025.jpg", "killed": "", "score": 1000, "id": 122}]'
+ ', "killed" : [], "rounds" : [], "currentState" : [ { "currentPhoto": 0 , "correctAnswer": 0 } ], "meta" : [ { "baseUrl": "photos/venuskopf/" } ]}';

//var jsonfile = '{"photos":[{"wins":[],"losses":[40,16],"uri":"xkopp-venus-15_109-017.jpg","killed":"","score":872,"id":50},{"wins":[50],"losses":[113],"uri":"17_129-016.jpg","killed":"","score":1000,"id":16},{"wins":[],"losses":[21],"uri":"venus_16_153-025.jpg","killed":"","score":936,"id":76},{"wins":[94],"losses":[],"uri":"17_138-007.jpg","killed":"","score":1064,"id":17},{"wins":[56],"losses":[],"uri":"venus_18-119-013.jpg","killed":"","score":1064,"id":105},{"wins":[],"losses":[84],"uri":"venus_19-104-001.jpg","killed":"","score":936,"id":75},{"wins":[],"losses":[116],"uri":"venus_16_149-024.jpg","killed":"","score":936,"id":107},{"wins":[31],"losses":[],"uri":"venus_19-122-014.jpg","killed":"","score":1064,"id":66},{"wins":[62],"losses":[],"uri":"venus_16_152-020.jpg","killed":"","score":1064,"id":77},{"wins":[89],"losses":[],"uri":"17_137-023.jpg","killed":"","score":1064,"id":39},{"wins":[69],"losses":[],"uri":"venus_19-099-013.jpg","killed":"","score":1064,"id":68},{"wins":[110],"losses":[],"uri":"venus_19-116-013.jpg","killed":"","score":1064,"id":104},{"wins":[24],"losses":[],"uri":"venus_18-122-001.jpg","killed":"","score":1064,"id":28},{"wins":[52],"losses":[],"uri":"venus_16_149-025.jpg","killed":"","score":1064,"id":109},{"wins":[],"losses":[121],"uri":"venus_16_146-025.jpg","killed":"","score":936,"id":49},{"wins":[],"losses":[83],"uri":"venus_16_161-027.jpg","killed":"","score":936,"id":41},{"wins":[],"losses":[43],"uri":"venus_16_153-012.jpg","killed":"","score":936,"id":33},{"wins":[51],"losses":[],"uri":"venus_18-123-003.jpg","killed":"","score":1064,"id":18},{"wins":[],"losses":[106],"uri":"venus_16_152-006.jpg","killed":"","score":936,"id":60},{"wins":[71],"losses":[],"uri":"17_124-022.jpg","killed":"","score":1064,"id":7},{"wins":[],"losses":[34],"uri":"venus_16_161-023.jpg","killed":"","score":936,"id":55},{"wins":[],"losses":[4],"uri":"venus_16_161-011.jpg","killed":"","score":936,"id":65},{"wins":[],"losses":[7],"uri":"venus_16_161-010.jpg","killed":"","score":936,"id":71},{"wins":[55],"losses":[],"uri":"venus_18-121-013.jpg","killed":"","score":1064,"id":34},{"wins":[82],"losses":[],"uri":"venus_18-120-022.jpg","killed":"","score":1064,"id":70},{"wins":[92],"losses":[],"uri":"venus_19-102-002.jpg","killed":"","score":1064,"id":27},{"wins":[],"losses":[88],"uri":"venus_19-114-006.jpg","killed":"","score":936,"id":93},{"wins":[0],"losses":[],"uri":"venus_16_161-025.jpg","killed":"","score":1064,"id":37},{"wins":[61],"losses":[],"uri":"venus_16_152-013.jpg","killed":"","score":1064,"id":64},{"wins":[],"losses":[18],"uri":"venus_19-115-008.jpg","killed":"","score":936,"id":51},{"wins":[],"losses":[77],"uri":"venus_16_153-003.jpg","killed":"","score":936,"id":62},{"wins":[14],"losses":[],"uri":"xkopp-venus-15_106-015.jpg","killed":"","score":1064,"id":99},{"wins":[],"losses":[74],"uri":"venus_16_161-002.jpg","killed":"","score":936,"id":85},{"wins":[],"losses":[80],"uri":"17_138-010.jpg","killed":"","score":936,"id":11},{"wins":[],"losses":[99],"uri":"xkopp-venus-15_113-006.jpg","killed":"","score":936,"id":14},{"wins":[75],"losses":[],"uri":"venus_19-111-020.jpg","killed":"","score":1064,"id":84},{"wins":[100],"losses":[],"uri":"venus_16_144-022.jpg","killed":"","score":1064,"id":26},{"wins":[57],"losses":[],"uri":"venus_18-123-008.jpg","killed":"","score":1064,"id":97},{"wins":[122],"losses":[],"uri":"venus_19-114-009.jpg","killed":"","score":1064,"id":46},{"wins":[114],"losses":[],"uri":"venus_16_161-016.jpg","killed":"","score":1064,"id":86},{"wins":[],"losses":[44],"uri":"venus_19-113-001.jpg","killed":"","score":936,"id":10},{"wins":[60],"losses":[],"uri":"venus_16_144-013.jpg","killed":"","score":1064,"id":106},{"wins":[],"losses":[104],"uri":"venus_19-121-001.jpg","killed":"","score":936,"id":110},{"wins":[20],"losses":[],"uri":"venus_16_145-012.jpg","killed":"","score":1064,"id":115},{"wins":[],"losses":[112],"uri":"17_139-001.jpg","killed":"","score":936,"id":6},{"wins":[],"losses":[63],"uri":"venus_19-119-001.jpg","killed":"","score":936,"id":36},{"wins":[47],"losses":[],"uri":"xkopp-venus-15_113-010.jpg","killed":"","score":1064,"id":13},{"wins":[],"losses":[118],"uri":"venus_19-111-003.jpg","killed":"","score":936,"id":59},{"wins":[120],"losses":[],"uri":"venus_18-122-004.jpg","killed":"","score":1064,"id":1},{"wins":[11],"losses":[],"uri":"venus_19-114-010.jpg","killed":"","score":1064,"id":80},{"wins":[87],"losses":[],"uri":"venus_19-100-002.jpg","killed":"","score":1064,"id":38},{"wins":[],"losses":[25],"uri":"venus_16_162-027.jpg","killed":"","score":936,"id":3},{"wins":[],"losses":[23],"uri":"xkopp-venus-15_112-001.jpg","killed":"","score":936,"id":12},{"wins":[],"losses":[72],"uri":"venus_16_144-010.jpg","killed":"","score":936,"id":98},{"wins":[],"losses":[29],"uri":"venus_16_161-003.jpg","killed":"","score":936,"id":79},{"wins":[33],"losses":[],"uri":"17_122-007.jpg","killed":"","score":1064,"id":43},{"wins":[59],"losses":[],"uri":"venus_16_144-029.jpg","killed":"","score":1064,"id":118},{"wins":[],"losses":[13],"uri":"xkopp-venus-15_111-015.jpg","killed":"","score":936,"id":47},{"wins":[2],"losses":[],"uri":"venus_16_161-015.jpg","killed":"","score":1064,"id":95},{"wins":[],"losses":[42],"uri":"venus_19-113-015.jpg","killed":"","score":936,"id":9},{"wins":[],"losses":[53],"uri":"17_129-001.jpg","killed":"","score":936,"id":8},{"wins":[],"losses":[109],"uri":"venus_19-115-009.jpg","killed":"","score":936,"id":52},{"wins":[],"losses":[15],"uri":"venus_19-116-011.jpg","killed":"","score":936,"id":103},{"wins":[],"losses":[27],"uri":"venus_19-104-012.jpg","killed":"","score":936,"id":92},{"wins":[32],"losses":[],"uri":"venus_16_146-012.jpg","killed":"","score":1064,"id":96},{"wins":[103],"losses":[],"uri":"venus_18-111-008.jpg","killed":"","score":1064,"id":15},{"wins":[6],"losses":[],"uri":"venus_16_154-002.jpg","killed":"","score":1064,"id":112},{"wins":[],"losses":[38],"uri":"venus_16_147-028.jpg","killed":"","score":936,"id":87},{"wins":[],"losses":[97],"uri":"venus_16_146-024.jpg","killed":"","score":936,"id":57},{"wins":[81],"losses":[],"uri":"17_119-011.jpg","killed":"","score":1064,"id":67},{"wins":[9],"losses":[],"uri":"17_122-006.jpg","killed":"","score":1064,"id":42},{"wins":[41],"losses":[],"uri":"venus_16_152-031.jpg","killed":"","score":1064,"id":83},{"wins":[],"losses":[73],"uri":"venus_19-106-005.jpg","killed":"","score":936,"id":102},{"wins":[],"losses":[78],"uri":"venus_19-105-002.jpg","killed":"","score":936,"id":90},{"wins":[102],"losses":[],"uri":"venus_16_161-006.jpg","killed":"","score":1064,"id":73},{"wins":[16],"losses":[],"uri":"venus_16_144-016.jpg","killed":"","score":1064,"id":113},{"wins":[],"losses":[115],"uri":"venus_19-097-011.jpg","killed":"","score":936,"id":20},{"wins":[],"losses":[66],"uri":"venus_16_161-024.jpg","killed":"","score":936,"id":31},{"wins":[],"losses":[1],"uri":"venus_16_162-002.jpg","killed":"","score":936,"id":120},{"wins":[12],"losses":[],"uri":"17_129-006.jpg","killed":"","score":1064,"id":23},{"wins":[],"losses":[37],"uri":"xkopp-venus-15_113-005.jpg","killed":"","score":936,"id":0},{"wins":[],"losses":[30],"uri":"xkopp-venus-15_113-007.jpg","killed":"","score":936,"id":19},{"wins":[10],"losses":[],"uri":"venus_19-119-016.jpg","killed":"","score":1064,"id":44},{"wins":[],"losses":[86],"uri":"17_124-011.jpg","killed":"","score":936,"id":114},{"wins":[79],"losses":[],"uri":"venus_16_145-019.jpg","killed":"","score":1064,"id":29},{"wins":[],"losses":[26],"uri":"xkopp-venus-15_113-019.jpg","killed":"","score":936,"id":100},{"wins":[],"losses":[45],"uri":"venus_16_162-003.jpg","killed":"","score":936,"id":119},{"wins":[98],"losses":[],"uri":"venus_16_161-012.jpg","killed":"","score":1064,"id":72},{"wins":[49],"losses":[],"uri":"17_138-008.jpg","killed":"","score":1064,"id":121},{"wins":[8],"losses":[],"uri":"venus_18-121-014.jpg","killed":"","score":1064,"id":53},{"wins":[117],"losses":[],"uri":"17_131-026.jpg","killed":"","score":1064,"id":101},{"wins":[76],"losses":[],"uri":"venus_18-123-007.jpg","killed":"","score":1064,"id":21},{"wins":[],"losses":[17],"uri":"venus_16_152-026.jpg","killed":"","score":936,"id":94},{"wins":[],"losses":[101],"uri":"venus_18-118-004.jpg","killed":"","score":936,"id":117},{"wins":[],"losses":[105],"uri":"xkopp-venus-15_109-016.jpg","killed":"","score":936,"id":56},{"wins":[],"losses":[95],"uri":"venus_18-123-001.jpg","killed":"","score":936,"id":2},{"wins":[],"losses":[67],"uri":"venus_16_153-021.jpg","killed":"","score":936,"id":81},{"wins":[50],"losses":[],"uri":"venus_19-100-028.jpg","killed":"","score":1064,"id":40},{"wins":[36],"losses":[],"uri":"venus_19-108-001.jpg","killed":"","score":1064,"id":63},{"wins":[],"losses":[68],"uri":"venus_19-098-002.jpg","killed":"","score":936,"id":69},{"wins":[],"losses":[46],"uri":"venus_16_151-025.jpg","killed":"","score":936,"id":122},{"wins":[65],"losses":[],"uri":"17_138-005.jpg","killed":"","score":1064,"id":4},{"wins":[93],"losses":[],"uri":"venus_19-114-007.jpg","killed":"","score":1064,"id":88},{"wins":[],"losses":[70],"uri":"venus_18-121-021.jpg","killed":"","score":936,"id":82},{"wins":[111],"losses":[],"uri":"xkopp-venus-15_109-014.jpg","killed":"","score":1064,"id":58},{"wins":[],"losses":[91],"uri":"venus_18-120-011.jpg","killed":"","score":936,"id":54},{"wins":[85],"losses":[],"uri":"venus_19-101-018.jpg","killed":"","score":1064,"id":74},{"wins":[5],"losses":[],"uri":"17_129-023.jpg","killed":"","score":1064,"id":108},{"wins":[107],"losses":[],"uri":"xkopp-venus-15_107-003.jpg","killed":"","score":1064,"id":116},{"wins":[],"losses":[48],"uri":"venus_19-108-010.jpg","killed":"","score":936,"id":35},{"wins":[90],"losses":[],"uri":"17_123-023.jpg","killed":"","score":1064,"id":78},{"wins":[],"losses":[108],"uri":"venus_16_145-020.jpg","killed":"","score":936,"id":5},{"wins":[],"losses":[58],"uri":"venus_19-116-006.jpg","killed":"","score":936,"id":111},{"wins":[],"losses":[64],"uri":"venus_19-109-005.jpg","killed":"","score":936,"id":61},{"wins":[],"losses":[96],"uri":"venus_19-111-006.jpg","killed":"","score":936,"id":32},{"wins":[54],"losses":[],"uri":"venus_19-099-016.jpg","killed":"","score":1064,"id":91},{"wins":[3],"losses":[],"uri":"17_139-013.jpg","killed":"","score":1064,"id":25},{"wins":[19],"losses":[],"uri":"venus_18-122-014.jpg","killed":"","score":1064,"id":30},{"wins":[35],"losses":[],"uri":"venus_16_146-021.jpg","killed":"","score":1064,"id":48},{"wins":[],"losses":[39],"uri":"venus_19-122-011.jpg","killed":"","score":936,"id":89},{"wins":[],"losses":[28],"uri":"17_139-012.jpg","killed":"","score":936,"id":24},{"wins":[119],"losses":[],"uri":"venus_19-104-009.jpg","killed":"","score":1064,"id":45}],"killed":[],"rounds":[{"percent":"0"}],"currentState":[{"currentPhoto":2,"correctAnswer":0}],"meta":[{"baseUrl":"photos/venuskopf/"}]}'

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

  $("#grid").empty();
  $("#canvas").show();

  for (var i = 0; i < rankingArray.length; i++) {
  
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
    
    if (rankingArray[i].killed > 0) {  
      $("#grid").append("<div class=\"gridItem off\"><div class=\"glass\">" + rankingArray[i].killed + "</div><img src=" + baseUrl + "" + rankingArray[i].uri + "></div>");
    } else {
      $("#grid").append("<div class=\"gridItem\"><img src=" + baseUrl + "" + rankingArray[i].uri + "></div>");
    }
    

  
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
if (currentPhoto == 0) { shuffle(json.photos); }
drawScreen();
makeTable();
makeRoundStats();


