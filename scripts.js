// AUS CURRENTPHOTO UND CURRENTOHOTO+1 IRGENDWIE DOCH LIEBER LINKS UND RECHTS MACHEN
// DIE BILDER BRAUCHEN NOCH NE ID UND "GEWONNEN GEGEN" UND "VERLOREN GEGEN"

var jsonfile = '{ "photos" : [' +
'{ "uri":"test-1.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-2.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-3.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-4.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-5.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-6.jpg" , "score":1000 , "wins":0 , "losses":0} ]}';

var json = JSON.parse(jsonfile);
var currentPhoto = -2;
var points = $.map(json.photos, function(value, index){
        return [value];
    });

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
  for (var i = 0; i < points.length; i++) {
    $("#completeTable table").append("<tr><td>" + i + ".</td><td>" + points[i].uri + "</td><td>" + points[i].score.toFixed(0) + "</td><td>" + points[i].wins + "</td><td>" + points[i].losses + "</td></tr>")
  }

}


function updatePhotos() {

  // CHECK LENGTH
  if (currentPhoto == (json.photos.length-2)) {
    shuffle(json.photos);
    currentPhoto = 0;
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
  $("#leftPhoto").attr("src","photos/" + json.photos[currentPhoto].uri);
  $("#rightPhoto").attr("src","photos/" + json.photos[currentPhoto+1].uri);
  
  $("#left .uri").text(json.photos[currentPhoto].uri);
  $("#left .wins").text("WINS: " + json.photos[currentPhoto].wins);
  $("#left .losses").text("LOSSES: " + json.photos[currentPhoto].losses);
  $("#left .score").text("SCORE: " + json.photos[currentPhoto].score);
  $("#left .chance").text("CHANCE: " + chances.left.toFixed(3));

  $("#right .uri").text(json.photos[currentPhoto+1].uri);
  $("#right .wins").text("WINS: " + json.photos[currentPhoto+1].wins);
  $("#right .losses").text("LOSSES: " + json.photos[currentPhoto+1].losses);
  $("#right .score").text("SCORE: " + json.photos[currentPhoto+1].score);
  $("#right .chance").text("CHANCE: " + chances.right.toFixed(3));

  makeTable();

}



$("#leftPhoto").click(function() {

  // DEBUGS
  console.log(json.photos[currentPhoto].uri + " (S:" + json.photos[currentPhoto].score.toFixed(0) + "|C:" + chances.left.toFixed(2) + "|W:" + json.photos[currentPhoto].wins + "|L:" + json.photos[currentPhoto].losses + ") wins against " + json.photos[currentPhoto+1].uri + " (S:" + json.photos[currentPhoto+1].score.toFixed(0) + "|C:" + chances.right.toFixed(2) + "|W:" + json.photos[currentPhoto+1].wins + "|L:" + json.photos[currentPhoto+1].losses + ").");

  // LEFT WINS
  json.photos[currentPhoto].wins++;
  json.photos[currentPhoto+1].losses++;
  
  // If left photo wins:
  json.photos[currentPhoto].score = json.photos[currentPhoto].score + KFactor * (1 - chances.left)
  json.photos[currentPhoto+1].score = json.photos[currentPhoto+1].score + KFactor * (0 - chances.right) 

  updatePhotos();

});

$("#rightPhoto").click(function() {

  // DEBUGS
  console.log(json.photos[currentPhoto+1].uri + " (S:" + json.photos[currentPhoto+1].score.toFixed(0) + "|C:" + chances.right.toFixed(2) + "|W:" + json.photos[currentPhoto+1].wins + "|L:" + json.photos[currentPhoto+1].losses + ") wins against " + json.photos[currentPhoto].uri + " (S:" + json.photos[currentPhoto].score.toFixed(0) + "|C:" + chances.left.toFixed(2) + "|W:" + json.photos[currentPhoto].wins + "|L:" + json.photos[currentPhoto].losses + ").");

  // RIGHT WINS
  json.photos[currentPhoto+1].wins++;
  json.photos[currentPhoto].losses++;
  
  // If right photowins:
  json.photos[currentPhoto+1].score = json.photos[currentPhoto+1].score + KFactor * (1 - chances.right)
  json.photos[currentPhoto].score = json.photos[currentPhoto].score + KFactor * (0 - chances.left)
    
  updatePhotos();
  
});



// INIT
shuffle(json.photos);
updatePhotos();

