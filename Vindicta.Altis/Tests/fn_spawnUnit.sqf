#include "..\OOP_Light\OOP_Light.h"

/*
Spawn a unit
*/

#include "..\OOP_Light\OOP_Light.h"
#define pr private

params ["_catID", "_subcatID", "_side"];

pr _template = switch (_side) do {
 case WEST: {tNATO};    
 case EAST: {tCSAT};
 case INDEPENDENT: {tAAF};
};

// Create a temporary location
pr _tempLoc = NEW("Location", [getPos player]);
CALLM2(_tempLoc, "setBorder", "circle", 3); // Circle with 3 meter radius

// Create group
pr _args = [_side, 0]; // Side, group type
pr _newGroup = NEW("Group", _args);

// Create unit
pr _args = [_template, _catID, _subcatID, -1, _newGroup];
pr _unit_0 = NEW("Unit", _args);

// Spawn the group
CALLM1(_newGroup, "spawn", _tempLoc);

// Delete the location
DELETE(_tempLoc);