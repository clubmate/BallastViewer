// DITT MUESSTE IRGENDWIE AUCH "REALTIME" BERECHNET SEIN, ALSO WENN SICH DER SCORE EINES
// ELEMENTS AENDERT, MUESSEN ALLE ANDEREN BILDER DIE DA MIT BERECHNET WURDEN GEUPDATET WERDEN, ODER?
//
// AUS CURRENTPHOTO UND CURRENTOHOTO+1 IRGENDWIE DOCH LIEBER LINKS UND RECHTS MACHEN
//
// DIE BILDER BRAUCHEN NOCH NE ID UND "GEWONNEN GEGEN" UND "VERLOREN GEGEN"

var jsonfile = '{ "photos" : [' +
'{ "uri":"test-1.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-2.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-3.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-4.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-5.jpg" , "score":1000 , "wins":0 , "losses":0},' +
'{ "uri":"test-6.jpg" , "score":1000 , "wins":0 , "losses":0} ]}';

var json = JSON.parse(jsonfile);
var currentPhoto = 0;
var points = $.map(json.photos, function(value, index){
        return [value];
    });

// The maximum number of points a player goes up or down by
// A 50% chance of winning (aka, both players have the same rating) means they go up or down by 32/2 = 16 points.
var KFactor = 32

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

function updatePhotos() {
 

// The actual Elo formula -- returns the probability of winning (num between 0 and 1)
getChanceOfWinning = (opponentRating, selfRating) => 1 / (1 + Math.pow(10, (opponentRating - selfRating) / 400))

chances = {
  left: getChanceOfWinning(json.photos[currentPhoto+1].score, json.photos[currentPhoto].score),
  right: getChanceOfWinning(json.photos[currentPhoto].score, json.photos[currentPhoto+1].score)
} 
 
 
  $("#leftPhoto").attr("src","photos/" + json.photos[currentPhoto].uri);
  $("#rightPhoto").attr("src","photos/" + json.photos[currentPhoto+1].uri);
  
//  $("#left").append(json.photos[currentPhoto].wins);
//  $("#right").append(json.photos[currentPhoto].wins);
  
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
  
//  var array = [{ "uri":"test-3.jpg" , "score":"1" , "wins":"7" , "losses":"0"},{ "uri":"test-4.jpg" , "score":"1" , "wins":"9" , "losses":"0"}];


  
  points.sort(function(a, b){
    var a1= a.score, b1= b.score;
    if(a1== b1) return 0;
    return a1< b1? 1: -1;
  });

//  console.log(points);


  $("#debug6 table").empty();
  for (var i = 0; i < points.length; i++) {
    console.log(points[i].uri);

    $("#debug6 table").append("<tr><td>" + i + ".</td><td>" + points[i].uri + "</td><td>" + points[i].score.toFixed(0) + "</td><td>" + points[i].wins + "</td><td>" + points[i].losses + "</td></tr>")

}


  $("#debug5").html(json.photos[0].uri + ": " + json.photos[0].wins + "<br/>" + json.photos[1].uri + ": " + json.photos[1].wins + "<br/>" + json.photos[2].uri + ": " + json.photos[2].wins + "<br/>" + json.photos[3].uri + ": " + json.photos[3].wins + "<br/>" + json.photos[4].uri + ": " + json.photos[4].wins + "<br/>" + json.photos[5].uri + ": " + json.photos[5].wins);

}

function checkPhotos() {

  $("#debug2").text(currentPhoto);

  if (currentPhoto == (json.photos.length-2)) {
    shuffle(json.photos);
    currentPhoto = 0;
  } else {
    currentPhoto += 2;
  }

}

$( "#shuffle" ).click(function() {
  
  if (currentPhoto == json.photos.length) {
    shuffle(json.photos);
    currentPhoto = 0;
  }
  
  $("#debug2").text(currentPhoto);
  $("#debug3").text(json.photos.length);
  
  $("#debug").append(json.photos[currentPhoto].uri + "<br/>");

//  $("#debug").append(json.photos[currentPhoto+1].uri + "<br/>");
//  
//  $("#debug").append(currentPhoto+1 + "/" + json.photos.length/2 + "<br/>");
  
  updatePhotos();
  
  currentPhoto += 2;
  
});

$("#leftPhoto").click(function() {
  json.photos[currentPhoto].wins++;
  json.photos[currentPhoto+1].losses++;
  
// Assuming it's win/loss, or 1 and 0...
// If playerA wins:
json.photos[currentPhoto].score = json.photos[currentPhoto].score + KFactor * (1 - chances.left)
json.photos[currentPhoto+1].score = json.photos[currentPhoto+1].score + KFactor * (0 - chances.right) 


  
  $("#debug").append(json.photos[currentPhoto].uri + " GEWINNT / " + json.photos[currentPhoto+1].uri + " VERLIERT<br/>");

  checkPhotos();
    
  updatePhotos();
});

$("#rightPhoto").click(function() {
  json.photos[currentPhoto+1].wins++;
  json.photos[currentPhoto].losses++;
  
// Assuming it's win/loss, or 1 and 0...
// If playerB wins:
json.photos[currentPhoto+1].score = json.photos[currentPhoto+1].score + KFactor * (1 - chances.right)
json.photos[currentPhoto].score = json.photos[currentPhoto].score + KFactor * (0 - chances.left)

  $("#debug").append(json.photos[currentPhoto+1].uri + " GEWINNT / " + json.photos[currentPhoto].uri + " VERLIERT<br/>");
  
  checkPhotos();
    
  updatePhotos();
  
});










//$("#debug").append("Player A wins.<br>Player A: " + JSON.stringify(json.photos[currentPhoto]) + "––– Expected chance of winning: " + chances.left.toFixed(3) + "<br>Player B: " + JSON.stringify(json.photos[currentPhotoRight]) + "––– Expected chance of winning: " + chances.right.toFixed(3));








// INIT
shuffle(json.photos);
updatePhotos();

