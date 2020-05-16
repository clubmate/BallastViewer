// AUS CURRENTPHOTO UND CURRENTOHOTO+1 IRGENDWIE DOCH LIEBER LINKS UND RECHTS MACHEN
// DETAILANSICHT PRO BILD GEGEN WELCHE ES GEWONNEN ODER VERLOREN HAT
// PRO DURCHLAUF MUSS ES EINE ZAHL GEBEN WIE NAH MAN SICH AN DIE ELO-PREDICTION ANGENAEHERT HAT 

//var jsonfile = '{ "photos" : [' +
//'{ "id":1 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":2 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":3 , "uri":"test-7.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":4 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":5 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] },' +
//'{ "id":20 , "uri":"test-8.jpg" , "score":1000 , "wins":[] , "losses":[] } ]}';

var jsonfile = '{ "photos" :' +
'[{"losses": [], "wins": [], "score": 1000, "id": 0, "uri": "xkopp-venus-15_113-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 1, "uri": "venus_18-122-004.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 2, "uri": "venus_16_151-028.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 3, "uri": "venus_18-123-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 4, "uri": "xkopp-venus-15_107-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 5, "uri": "venus_16_162-027.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 6, "uri": "17_138-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 7, "uri": "xkopp-venus-15_107-019.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 8, "uri": "venus_14_99-021-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 9, "uri": "venus_16_145-020.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 10, "uri": "17_139-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 11, "uri": "17_124-022.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 12, "uri": "17_129-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 13, "uri": "venus_19-113-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 14, "uri": "venus_19-113-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 15, "uri": "17_138-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 16, "uri": "xkopp-venus-15_112-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 17, "uri": "xkopp-venus-15_113-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 18, "uri": "xkopp-venus-15_113-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 19, "uri": "venus_16_150-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 20, "uri": "venus_18-110-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 21, "uri": "venus_18-110-019.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 22, "uri": "venus_18-111-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 23, "uri": "17_129-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 24, "uri": "venus_16_148-029.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 25, "uri": "17_138-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 26, "uri": "17_120-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 27, "uri": "venus_18-123-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 28, "uri": "xkopp-venus-15_113-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 29, "uri": "venus_19-097-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 30, "uri": "venus_14_100-012-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 31, "uri": "venus_18-123-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 32, "uri": "xkopp-venus-15_107-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 33, "uri": ".DS_Store"}, {"losses": [], "wins": [], "score": 1000, "id": 34, "uri": "17_129-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 35, "uri": "17_139-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 36, "uri": "17_129-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 37, "uri": "17_139-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 38, "uri": "venus_16_144-022.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 39, "uri": "venus_19-102-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 40, "uri": "venus_14_99-002-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 41, "uri": "17_130-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 42, "uri": "venus_18-122-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 43, "uri": "venus_16_150-028.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 44, "uri": "venus_16_145-019.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 45, "uri": "17_120-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 46, "uri": "venus_18-122-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 47, "uri": "venus_18-119-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 48, "uri": "venus_16_150-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 49, "uri": "xkopp-venus-15_108-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 50, "uri": "venus_14_98-011-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 51, "uri": "venus_16_161-024.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 52, "uri": "venus_19-111-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 53, "uri": "venus_16_153-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 54, "uri": "venus_18-121-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 55, "uri": "venus_19-108-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 56, "uri": "17_119-019.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 57, "uri": "venus_19-119-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 58, "uri": "17_123-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 59, "uri": "venus_16_161-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 60, "uri": "venus_19-100-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 61, "uri": "venus_14_99-023-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 62, "uri": "venus_14_99-014-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 63, "uri": "venus_16_146-022.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 64, "uri": "venus_16_146-020.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 65, "uri": "17_137-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 66, "uri": "venus_14_99-005-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 67, "uri": "venus_19-100-028.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 68, "uri": "xkopp-venus-15_109-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 69, "uri": "venus_16_161-027.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 70, "uri": "xkopp-venus-15_109-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 71, "uri": "17_122-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 72, "uri": "17_122-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 73, "uri": "venus_19-119-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 74, "uri": "venus_19-104-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 75, "uri": "venus_19-114-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 76, "uri": "venus_16_164-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 77, "uri": "xkopp-venus-15_111-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 78, "uri": "venus_16_146-021.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 79, "uri": "venus_16_146-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 80, "uri": "venus_16_146-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 81, "uri": "xkopp-venus-15_109-017.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 82, "uri": "venus_19-115-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 83, "uri": "venus_19-115-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 84, "uri": "venus_18-121-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 85, "uri": "venus_18-120-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 86, "uri": "venus_16_161-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 87, "uri": "xkopp-venus-15_109-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 88, "uri": "xkopp-venus-15_108-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 89, "uri": "xkopp-venus-15_108-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 90, "uri": "venus_16_146-024.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 91, "uri": "venus_16_146-026.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 92, "uri": "xkopp-venus-15_108-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 93, "uri": "17_136-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 94, "uri": "xkopp-venus-15_109-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 95, "uri": "venus_19-111-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 96, "uri": "venus_16_152-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 97, "uri": "venus_19-109-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 98, "uri": "venus_16_153-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 99, "uri": "venus_18-121-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 100, "uri": "venus_19-108-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 101, "uri": "17_119-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 102, "uri": "venus_16_153-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 103, "uri": "venus_16_152-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 104, "uri": "venus_19-110-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 105, "uri": "xkopp-venus-15_108-004.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 106, "uri": "xkopp-venus-15_108-021.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 107, "uri": "venus_16_161-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 108, "uri": "venus_19-122-014.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 109, "uri": "venus_14_97-020-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 110, "uri": "17_119-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 111, "uri": "venus_14_99-003-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 112, "uri": "venus_19-099-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 113, "uri": "venus_19-098-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 114, "uri": "venus_18-120-022.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 115, "uri": "venus_16_161-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 116, "uri": "venus_16_146-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 117, "uri": "venus_16_161-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 118, "uri": "venus_16_161-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 119, "uri": "venus_19-101-018.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 120, "uri": "venus_19-104-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 121, "uri": "venus_16_153-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 122, "uri": "venus_14_100-002-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 123, "uri": "venus_16_152-020.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 124, "uri": "17_123-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 125, "uri": "venus_16_161-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 126, "uri": "venus_14_99-017-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 127, "uri": "venus_16_161-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 128, "uri": "venus_16_152-024.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 129, "uri": "venus_19-114-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 130, "uri": "venus_16_153-021.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 131, "uri": "venus_18-121-021.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 132, "uri": "venus_16_152-031.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 133, "uri": "venus_19-111-020.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 134, "uri": "venus_16_161-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 135, "uri": "venus_16_161-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 136, "uri": "venus_16_147-028.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 137, "uri": "xkopp-venus-15_109-009.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 138, "uri": "venus_19-114-007.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 139, "uri": "venus_19-122-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 140, "uri": "venus_19-105-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 141, "uri": "venus_19-099-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 142, "uri": "17_122-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 143, "uri": "venus_19-104-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 144, "uri": "venus_19-114-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 145, "uri": "venus_16_152-026.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 146, "uri": "venus_16_161-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 147, "uri": "venus_14_99-006-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 148, "uri": "venus_16_146-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 149, "uri": "venus_18-119-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 150, "uri": "venus_14_96-010-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 151, "uri": "venus_18-123-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 152, "uri": "venus_16_144-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 153, "uri": "xkopp-venus-15_106-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 154, "uri": "venus_18-110-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 155, "uri": "xkopp-venus-15_113-019.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 156, "uri": "17_131-026.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 157, "uri": "venus_18-122-018.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 158, "uri": "venus_14_98-004-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 159, "uri": "venus_19-106-005.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 160, "uri": "venus_19-116-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 161, "uri": "venus_19-116-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 162, "uri": "venus_18-119-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 163, "uri": "venus_16_144-013.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 164, "uri": "venus_16_149-024.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 165, "uri": "17_129-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 166, "uri": "venus_16_145-017.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 167, "uri": "venus_16_149-025.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 168, "uri": "xkopp-venus-15_107-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 169, "uri": "venus_19-121-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 170, "uri": "venus_19-116-006.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 171, "uri": "venus_16_150-022.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 172, "uri": "venus_14_99-009-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 173, "uri": "venus_16_154-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 174, "uri": "venus_16_144-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 175, "uri": "xkopp-venus-15_107-016.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 176, "uri": "17_124-011.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 177, "uri": "venus_16_145-012.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 178, "uri": "xkopp-venus-15_107-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 179, "uri": "venus_16_162-029.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 180, "uri": "venus_14_99-015-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 181, "uri": "venus_18-119-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 182, "uri": "venus_16_150-023.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 183, "uri": "venus_18-118-004.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 184, "uri": "venus_14_99-004-fussel.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 185, "uri": "venus_16_144-029.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 186, "uri": "xkopp-venus-15_107-001.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 187, "uri": "venus_16_162-003.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 188, "uri": "xkopp-venus-15_107-015.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 189, "uri": "xkopp-venus-15_106-010.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 190, "uri": "venus_16_162-002.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 191, "uri": "17_138-008.jpg"}, {"losses": [], "wins": [], "score": 1000, "id": 192, "uri": "venus_16_151-025.jpg"}]'
+ '}';

var json = JSON.parse(jsonfile);
var currentPhoto = -2;
var points = $.map(json.photos, function(value, index){
        return [value];
    });
var correctAnswer = 0;
var round = 1;

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
  $("#leftPhoto").attr("src","photos/venuskopf/" + json.photos[currentPhoto].uri);
  $("#rightPhoto").attr("src","photos/venuskopf/" + json.photos[currentPhoto+1].uri);
   
  $("#previewLeftPhoto").attr("src","photos/venuskopf/" + json.photos[currentPhoto].uri);
  $("#previewRightPhoto").attr("src","photos/venuskopf/" + json.photos[currentPhoto+1].uri);
 
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


$("#leftPhoto").click(function() {

  leftPhotoWins();

});

$("#rightPhoto").click(function() {

  rightPhotoWins();
  
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


