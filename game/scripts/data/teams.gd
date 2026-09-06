class_name Teams
extends RefCounted

# All franchises here are invented. Colours are picked to stay separable
# against each other and to keep white jersey numbers legible on the primary.

enum Conf { EAST, WEST }

const DEFS := [
	# --- Eastern Conference ---------------------------------------------------
	{"city": "Bayview", "name": "Breakers", "abbr": "BAY", "conf": Conf.EAST,
		"primary": "#1f6f8b", "secondary": "#f2e3c6", "accent": "#0d3b4a"},
	{"city": "Ironport", "name": "Anchors", "abbr": "IRN", "conf": Conf.EAST,
		"primary": "#2b2f3a", "secondary": "#c9a227", "accent": "#4a5162"},
	{"city": "Northgate", "name": "Wolves", "abbr": "NOR", "conf": Conf.EAST,
		"primary": "#5a6472", "secondary": "#e4e9ef", "accent": "#2b313a"},
	{"city": "Steel City", "name": "Forge", "abbr": "STL", "conf": Conf.EAST,
		"primary": "#3d3d3d", "secondary": "#e07b1f", "accent": "#7a7a7a"},
	{"city": "Highland", "name": "Stags", "abbr": "HLD", "conf": Conf.EAST,
		"primary": "#7d1f3a", "secondary": "#d9c48a", "accent": "#42101f"},
	{"city": "Frostbay", "name": "Glaciers", "abbr": "FRO", "conf": Conf.EAST,
		"primary": "#4a83c4", "secondary": "#eef4fb", "accent": "#1e4675"},
	{"city": "Maple Heights", "name": "Owls", "abbr": "MPL", "conf": Conf.EAST,
		"primary": "#6a4b2a", "secondary": "#f0d9a8", "accent": "#3a2714"},
	{"city": "Kingsford", "name": "Monarchs", "abbr": "KNG", "conf": Conf.EAST,
		"primary": "#4b2e83", "secondary": "#ffcf3f", "accent": "#2a1750"},
	{"city": "Harbor Point", "name": "Gulls", "abbr": "HRB", "conf": Conf.EAST,
		"primary": "#0f5f9a", "secondary": "#f5f7f8", "accent": "#c0392b"},
	{"city": "Emberton", "name": "Blaze", "abbr": "EMB", "conf": Conf.EAST,
		"primary": "#c0392b", "secondary": "#f6c453", "accent": "#6b1d14"},
	{"city": "Riverton", "name": "Rapids", "abbr": "RIV", "conf": Conf.EAST,
		"primary": "#149a80", "secondary": "#e8f6f2", "accent": "#0a4c40"},
	{"city": "Lakeshore", "name": "Pilots", "abbr": "LKS", "conf": Conf.EAST,
		"primary": "#1d3f6e", "secondary": "#c8d4e3", "accent": "#8fa8c8"},
	{"city": "Granite Falls", "name": "Quarry", "abbr": "GRN", "conf": Conf.EAST,
		"primary": "#6e6a63", "secondary": "#dcd6c8", "accent": "#3b3833"},
	{"city": "Nova Springs", "name": "Comets", "abbr": "NOV", "conf": Conf.EAST,
		"primary": "#12204a", "secondary": "#7fe0ff", "accent": "#3a5ba0"},
	{"city": "Oakfield", "name": "Lumberjacks", "abbr": "OAK", "conf": Conf.EAST,
		"primary": "#2f5d34", "secondary": "#e6dbc2", "accent": "#17331b"},

	# --- Western Conference ---------------------------------------------------
	{"city": "Sunridge", "name": "Solar", "abbr": "SUN", "conf": Conf.WEST,
		"primary": "#e8862a", "secondary": "#3a2410", "accent": "#f7c85c"},
	{"city": "Cascade", "name": "Timber", "abbr": "CAS", "conf": Conf.WEST,
		"primary": "#2e6b3d", "secondary": "#f1ead6", "accent": "#17402a"},
	{"city": "Redrock", "name": "Rattlers", "abbr": "RED", "conf": Conf.WEST,
		"primary": "#9b2d20", "secondary": "#e4c9a0", "accent": "#5c1710"},
	{"city": "Gulfside", "name": "Marlins", "abbr": "GLF", "conf": Conf.WEST,
		"primary": "#1b9aaa", "secondary": "#062730", "accent": "#7fd8e0"},
	{"city": "Palm Harbor", "name": "Cyclones", "abbr": "PLM", "conf": Conf.WEST,
		"primary": "#6b3fa0", "secondary": "#f0e9a0", "accent": "#3a1f5c"},
	{"city": "Vega City", "name": "Vipers", "abbr": "VEG", "conf": Conf.WEST,
		"primary": "#1c1c22", "secondary": "#8fd14f", "accent": "#3c8c2a"},
	{"city": "Copper Ridge", "name": "Miners", "abbr": "COP", "conf": Conf.WEST,
		"primary": "#a35a2a", "secondary": "#1d1a17", "accent": "#d99a5c"},
	{"city": "Silver Mesa", "name": "Coyotes", "abbr": "SLV", "conf": Conf.WEST,
		"primary": "#8c8f96", "secondary": "#3a2f28", "accent": "#c8a15a"},
	{"city": "Crescent Bay", "name": "Tide", "abbr": "CRB", "conf": Conf.WEST,
		"primary": "#0d7c8c", "secondary": "#f2f7f6", "accent": "#054752"},
	{"city": "Dust Bowl", "name": "Drifters", "abbr": "DST", "conf": Conf.WEST,
		"primary": "#b08d55", "secondary": "#2b2118", "accent": "#e0c48a"},
	{"city": "Port Arden", "name": "Voyagers", "abbr": "PRT", "conf": Conf.WEST,
		"primary": "#2a4d8f", "secondary": "#f6a821", "accent": "#16295a"},
	{"city": "Quarry Hill", "name": "Hammers", "abbr": "QRY", "conf": Conf.WEST,
		"primary": "#5b2c6f", "secondary": "#d7bde2", "accent": "#301539"},
	{"city": "Saltflat", "name": "Scorpions", "abbr": "SLT", "conf": Conf.WEST,
		"primary": "#c9a227", "secondary": "#241f14", "accent": "#efd97a"},
	{"city": "Twin Peaks", "name": "Summit", "abbr": "TWN", "conf": Conf.WEST,
		"primary": "#37474f", "secondary": "#eceff1", "accent": "#78909c"},
	{"city": "Westbrook", "name": "Wranglers", "abbr": "WST", "conf": Conf.WEST,
		"primary": "#7b3f00", "secondary": "#f0e2c4", "accent": "#c07830"},
]

const ARENAS := [
	{"name": "The Cannery", "floor": "#c8934f", "wall": "#241a12",
		"seats": "#6b2f2f", "outdoor": false},
	{"name": "Pinewood Gym", "floor": "#d8b072", "wall": "#3a2c1e",
		"seats": "#5a4632", "outdoor": false},
	{"name": "Dock Street", "floor": "#7e8a7f", "wall": "#2a3330",
		"seats": "#3f4a44", "outdoor": true},
	{"name": "Sunset Blacktop", "floor": "#6d7378", "wall": "#1b2430",
		"seats": "#2f3a44", "outdoor": true},
]


static func conference_name(conf: int) -> String:
	return "Eastern" if conf == Conf.EAST else "Western"
