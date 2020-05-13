var jsonfile = '{ "photos" : [' +
'{ "uri":"test-1.jpg" , "score":1 , "wins":0 , "losses":0},' +
'{ "uri":"test-2.jpg" , "score":1 , "wins":0 , "losses":0},' +
'{ "uri":"test-3.jpg" , "score":1 , "wins":0 , "losses":0},' +
'{ "uri":"test-4.jpg" , "score":1 , "wins":0 , "losses":0},' +
'{ "uri":"test-5.jpg" , "score":1 , "wins":0 , "losses":0},' +
'{ "uri":"test-6.jpg" , "score":1 , "wins":0 , "losses":0} ]}';

var json = JSON.parse(jsonfile);
var currentPhoto = 0;
var points = $.map(json.photos, function(value, index){
        return [value];
    });

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
 
  $("#leftPhoto").attr("src","photos/" + json.photos[currentPhoto].uri);
  $("#rightPhoto").attr("src","photos/" + json.photos[currentPhoto+1].uri);
  
//  $("#left").append(json.photos[currentPhoto].wins);
//  $("#right").append(json.photos[currentPhoto].wins);
  
  $("#left .uri").text(json.photos[currentPhoto].uri);
  $("#left .wins").text("WINS: " + json.photos[currentPhoto].wins);
  $("#left .losses").text("LOSSES: " + json.photos[currentPhoto].losses);
  
  $("#right .uri").text(json.photos[currentPhoto+1].uri);
  $("#right .wins").text("WINS: " + json.photos[currentPhoto+1].wins);
  $("#right .losses").text("LOSSES: " + json.photos[currentPhoto+1].losses);
  
//  var array = [{ "uri":"test-3.jpg" , "score":"1" , "wins":"7" , "losses":"0"},{ "uri":"test-4.jpg" , "score":"1" , "wins":"9" , "losses":"0"}];


  
  points.sort(function(a, b){
    var a1= a.wins, b1= b.wins;
    if(a1== b1) return 0;
    return a1< b1? 1: -1;
  });

  console.log(points);


  $("#debug6 table").empty();
  for (var i = 0; i < points.length; i++) {
    console.log(points[i].uri);

    $("#debug6 table").append("<tr><td>" + i + ".</td><td>" + points[i].uri + "</td><td>" + points[i].score + "</td><td>" + points[i].wins + "</td><td>" + points[i].losses + "</td></tr>")

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
  
  $("#debug").append(json.photos[currentPhoto].uri + " GEWINNT / " + json.photos[currentPhoto+1].uri + " VERLIERT<br/>");

  checkPhotos();
    
  updatePhotos();
});

$("#rightPhoto").click(function() {
  json.photos[currentPhoto+1].wins++;
  json.photos[currentPhoto].losses++;
  
  $("#debug").append(json.photos[currentPhoto+1].uri + " GEWINNT / " + json.photos[currentPhoto].uri + " VERLIERT<br/>");
  
  checkPhotos();
    
  updatePhotos();
  
});

// INIT
shuffle(json.photos);
updatePhotos();

