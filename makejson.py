import json
import os

path = "photos/venuskopf"
photoURIs = os.listdir(path)
all = []

for num, i in enumerate(photoURIs): 
 
   # python object to be appended 
   y = { "id":num, 
         "uri": i, 
         "score": 1000,
         "wins":[],
         "losses":[],
         "killed":"",
       } 
  
  
    # appending data 
   if i != ".DS_Store":
      all.append(y) 
   
   

 
   
t = json.dumps(all, indent=4)
print(t)  

with open('photos.json', 'w') as outfile:
    json.dump(all, outfile)