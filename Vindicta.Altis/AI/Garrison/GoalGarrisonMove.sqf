#include "common.hpp"
/*
Goal for a garrison to move somewhere
*/

#define pr private

CLASS("GoalGarrisonMove", "Goal")

	// ----------------------------------------------------------------------
	// |            C A L C U L A T E   R E L E V A N C E
	// ----------------------------------------------------------------------
	// Calculates desireability to choose this goal for a given _AI
	// Inherited classes must implement this
	
	/*
	STATIC_METHOD("calculateRelevance") {
		params [ ["_thisClass", "", [""]], ["_AI", "", [""]]];
		
		// Return relevance
		GOAL_RELEVANCE_GARRISON_MOVE

	} ENDMETHOD;
	*/

	// Must use this method to get the move radius if we are moving to a location
	STATIC_METHOD("getLocationMoveRadius") {
		params [P_THISCLASS, P_OOP_OBJECT("_loc")];

		pr _border = CALLM0(_loc, "getBorder"); // [center, a, b, angle, isRectangle, c]
		pr _minSize = (_border#1) min (_border#2);

		(_minSize min 160) max 400 // Clamp it within some reasonable range
	} ENDMETHOD;

ENDCLASS;