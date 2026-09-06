class_name Names
extends RefCounted

const FIRST := [
	"Andre", "Marcus", "Deshawn", "Tyrell", "Jalen", "Corey", "Devin", "Ramon",
	"Isaiah", "Trey", "Damon", "Elijah", "Kwame", "Nate", "Vince", "Omar",
	"Rashad", "Jamal", "Cedric", "Malik", "Terrence", "Darius", "Quincy", "Lorenzo",
	"Bryce", "Kendrick", "Xavier", "Anton", "Dwight", "Reggie", "Sean", "Miles",
	"Curtis", "Tobias", "Zane", "Hakim", "Julius", "Emmett", "Rico", "Solomon",
	"Bruno", "Luka", "Nikola", "Goran", "Rudy", "Mateo", "Sergio", "Yannick",
	"Kai", "Ove", "Dario", "Tarik", "Vlad", "Anders", "Milos", "Bojan",
	"Clint", "Hollis", "Sylvester", "Ozzie", "Duke", "Ellis", "Roman", "Wade",
]

const LAST := [
	"Hollins", "Whitfield", "Cardwell", "Bass", "Duplessis", "Kingman", "Vaughn",
	"Sackett", "Marrero", "Okafor", "Beaumont", "Tunstall", "Grier", "Ashby",
	"Ivey", "Pridgen", "Callahan", "Mensah", "Radic", "Delacroix", "Sorenson",
	"Bristow", "Naismith", "Yarborough", "Trombley", "Peavy", "Sandoval", "Kubo",
	"Antetoku", "Bergeron", "Chandler", "Doran", "Ellington", "Fournette",
	"Gainey", "Halstead", "Ingram", "Jessup", "Kilgore", "Larkin", "Mowry",
	"Nesbitt", "Oyelaran", "Pettigrew", "Quintero", "Rasmussen", "Stoudt",
	"Thibodeaux", "Ulrich", "Vukovic", "Wexler", "Yancey", "Zerbe", "Alcott",
	"Bowerman", "Crenshaw", "Dupree", "Ferrante", "Gallo", "Hurtado", "Ito",
	"Jankovic", "Kaminski", "Leblanc", "Muldoon", "Novak", "Oduya", "Poirier",
]

const NICK := [
	"The Fridge", "Ice", "Sky", "Doc", "Boots", "Twitch", "Cannon", "Sarge",
	"Peanut", "Freight Train", "Pogo", "Tank", "Silk", "Ghost", "Thunder",
]

static func first_name(rng: RandomNumberGenerator) -> String:
	return FIRST[rng.randi() % FIRST.size()]

static func last_name(rng: RandomNumberGenerator) -> String:
	return LAST[rng.randi() % LAST.size()]
