#include "..\OOP_Light\OOP_Light.h"
#include "..\Message\Message.hpp"
#include "..\MessageTypes.hpp"
#include "UndercoverMonitor.hpp"
#include "..\modCompatBools.sqf"

/*
Undercover Monitor: Determines if the enemy should identify a player as 
a hostile or a civilian by changing the player unit's captive status. 

NOTE: This script is not meant to modify how or if the AI sees the player. 
That is handled only by the core game's AI.

Description of different undercover states:

<UNDERCOVER>: Not wanted, not suspicious, player is "captive" and basically a civilian

<SUSPICIOUS>: Between suspicion SUSPICIOUS (#define SUSPICIOUS value) and <1, player may be suspicious to enemy. 

<WANTED>: The player is spotted as a hostile (i.e. armed, armored, or in a military vehicle with suspicion >= 1). A "killzone" is placed around the
player unit. Player can only go back to undercover if they are 1) unseen by enemy, and 2) outside "killzone" marker.

Date: December 2018
Author: Sparker, Marvis
*/

gMsgLoopUndercover = NEW("MessageLoop", []);
CALL_METHOD(gMsgLoopUndercover, "setDebugName", ["Undercover thread"]);

#define pr private
#define DEBUG

	// ----------------------------------------------------------------------
	// |                U N D E R C O V E R  D E F I N E S                  |
	// ----------------------------------------------------------------------

#define SUSPICIOUS 0.6								// suspiciousness gained while being "suspicious" 
#define SUSP_CROUCH 0.1								// suspiciousness gained crouching
#define SUSP_PRONE 0.2								// suspiciousness gained prone
#define SUSP_SPEEDMAX 0.35							// suspiciousness gained for movement speed
#define SUSP_NOROADS 80								// distance that is too far from road to not be suspicious

// suspicion values for each equipment type
#define SUSP_UNIFORM 0.7							// suspiciousness gained for mil uniform
#define SUSP_VEST 0.5								// suspiciousness gained for mil vest
#define SUSP_NVGS 0.7								// suspiciousness gained for NVGs
#define SUSP_HEADGEAR 0.7							// suspiciousness gained for mil headgear
#define SUSP_FACEWEAR 0.1							// suspiciousness gained for mil facewear
#define SUSP_BACKPACK 0.3							// suspiciousness gained for mil backpack

// values for
#define SUSP_VEH_DIST 100							// distance at which suspiciousness starts increasing based on SUSP_VEH_DIST_MULT 
#define SUSP_VEH_DIST_MIN 15						// distance at which player is too close to be undercover with suspicious gear in a vehicle
#define SUSP_VEH_DIST_MULT 1.12/SUSP_VEH_DIST;		// multiplier for distance-based fade-in of suspiciousness variable

#define TIME_SEEN 5									// time it takes, in seconds, for player unit to go from "seen" to "unseen"
#define TIME_HOSTILITY 10							// time in seconds player unit is overt after a hostile action
#define TIME_UNSEEN_WANTED_EXIT -240				// time in seconds it takes for player unit to be unseen before going from WANTED state back to UNDERCOVER state

#define WANTED_CIRCLE_RADIUS 500

	// ----------------------------------------------------------------------
	// |                       S Q F  F U N C T I O N S 					|
	// ----------------------------------------------------------------------		

	fnc_suspGear = {
		params ["_unit"];

		pr _suspGear = 0;
		pr _suspGearVeh = 0;

		if !((uniform _unit in civUniforms) or (uniform _unit == "")) then { _suspGear = _suspGear + SUSP_UNIFORM; _suspGearVeh = _suspGearVeh + SUSP_UNIFORM; };
		if !((headgear _unit in civHeadgear) or (headgear _unit == "")) then { _suspGear = _suspGear + SUSP_HEADGEAR; _suspGearVeh = _suspGearVeh + SUSP_HEADGEAR; }; 
		if !((goggles _unit in civFacewear) or (goggles _unit == "")) then { _suspGear = _suspGear + SUSP_FACEWEAR; _suspGearVeh = _suspGearVeh + SUSP_FACEWEAR; };
		if !((vest _unit in civVests) or (vest _unit == "")) then { _suspGear = _suspGear + SUSP_VEST; _suspGearVeh = _suspGearVeh + SUSP_VEST; };
		if (hmd _unit != "") then { _suspGear = _suspGear + SUSP_NVGS; };
		if !((backpack _unit in civBackpacks) or (backpack _unit == "")) then { _suspGear = _suspGear + SUSP_BACKPACK; };

		if !( primaryWeapon _unit in civWeapons) then { _suspGear = 1; };
		if !( secondaryWeapon _unit in civWeapons) then { _suspGear = 1; };
	
		_unit setVariable ["suspGear", _suspGear];
		_unit setVariable ["suspGearVeh", _suspGearVeh];
	};

	// ----------------------------------------------------------------------
	// |                       M A I N  C L A S S                           |
	// ----------------------------------------------------------------------

CLASS("undercoverMonitor", "MessageReceiver")

	VARIABLE("unit"); // Unit for which this script is running (player)
	VARIABLE("timer"); // Timer which will send SMON_MESSAGE_PROCESS message every second or so
	
	// ----------------------------------------------------------------------
	// |                              N E W                                 |
	// ----------------------------------------------------------------------
	
	METHOD("new") {
		params [["_thisObject", "", [""]], ["_unit", objNull, [objNull]]];

		// Unit (player) variables
		SETV(_thisObject, "unit", _unit);
		_unit setVariable ["undercoverMonitor", _thisObject];
						
		pr _msg = MESSAGE_NEW();
		MESSAGE_SET_DESTINATION(_msg, _thisObject);
		MESSAGE_SET_TYPE(_msg, SMON_MESSAGE_PROCESS);
		pr _updateInterval = 1.0;
		pr _args = [_thisObject, _updateInterval, _msg, gTimerServiceMain];
		pr _timer = NEW("Timer", _args);
		SETV(_thisObject, "timer", _timer);

		[_unit] call fnc_suspGear;
		_unit setCaptive true;

		// important player variables
		_unit setVariable [UNDERCOVER_EXPOSED, false, true];				// GLOBAL: true if player unit's exposure is above some threshold while he's in a vehicle
		_unit setVariable [UNDERCOVER_WANTED, false, true];					// GLOBAL: if true player unit is hostile and "setCaptive false"
		_unit setVariable [UNDERCOVER_SUSPICIOUS, false, true];				// GLOBAL: true if player is suspicious (suspicion variable >= SUSPICIOUS #define)

		_unit setVariable ["suspicion", 0];									// final suspiciousness of player
		_unit setVariable ["timeSeen", 0];
		_unit setVariable ["timeHostility", 0];
			
		_unit setVariable ["bSeen", false];									// true if unit is currently seen by an enemy

		_unit setVariable ["nearestEnemyDist", -1];							// distance to nearest unit in group that has spotted player
		_unit setVariable ["nearestEnemy", objNull];						// enemy closest to player, taken from group that has spotted player last

		_unit setVariable ["bodyExposure", 1.0];							// value for how exposed player is inside current vehicle seat
		_unit setVariable ["eyePosOld", [0, 0, 0]];				
		_unit setVariable ["eyePosOldVeh", [0, 0, 0]];		

		// more efficient way of checking player equipment suspiciousness only when loadout changes, this is a CBA event handler
		["loadout", { 
			params ["_unit", "_newLoadout"];
			[_unit] call fnc_suspGear;
    	}] call CBA_fnc_addPlayerEventHandler;

    	// used for checking when player has last commited a hostile act
    	_unit addEventHandler ["FiredMan", {
			params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_magazine", "_projectile", "_gunner"];
			_unit setVariable ["timeHostility", time + TIME_HOSTILITY];
		}];

		#ifdef DEBUG
			_unit setVariable ["bInVeh", false];					// true while player unit is in vehicle
			_unit setVariable ["bInMarker", false];					// true while player unit is in wanted marker
			call compile preprocessFileLineNumbers "UI_OOP\UIUndercoverDebug_Update.sqf";

		#endif	

	} ENDMETHOD;
	
	// ----------------------------------------------------------------------
	// |                            D E L E T E                             |
	// ----------------------------------------------------------------------
	
	METHOD("delete") {
		params [["_thisObject", "", [""]]];
		
		// Delete the timer
		pr _timer = GETV(_thisObject, "timer");
		DELETE(_timer);
		
	} ENDMETHOD;
	
	METHOD("getMessageLoop") {
		gMsgLoopUndercover
	} ENDMETHOD;
	
	// ----------------------------------------------------------------------
	// |                     H A N D L E  M E S S A G E                     |
	// ----------------------------------------------------------------------
	
	METHOD("handleMessage") {
		params [ ["_thisObject", "", [""]] , ["_msg", [], [[] ]] ];
		
		// Unpack the message
		pr _msgType = _msg select MESSAGE_ID_TYPE;
		
		switch (_msgType) do {
		
			// executed every interval: real-time evaluation of player unit's suspicion/suspiciousness
			case SMON_MESSAGE_PROCESS: {

				pr _unit = GETV(_thisObject, "unit");
				pr _bSeen = _unit getVariable "bSeen";
				pr _bInVeh = false;
				pr _removeWanted = false; // if true, WANTED state is removed in current interval
				pr _suspicion = 0;
				pr _timeHostility = _unit getVariable "timeHostility";
				pr _timeSeen = _unit getVariable "timeSeen";
				pr _suspGear = _unit getVariable "suspGear"; // equipment suspiciousness as determined by CBA "loadout" event handler
				pr _suspGearVeh = _unit getVariable "suspGearVeh"; // (in vehicle) equipment suspiciousness as determined by CBA "loadout" event handler
				pr _nearestEnemy = _unit getVariable "nearestEnemy"; // enemy closest to player, from group sent to SMON_MESSAGE_BEING_SPOTTED
				if (!(isNull objectParent _unit)) then { _bInVeh = true; }; // player unit is in vehicle
				if !(currentWeapon _unit in civWeapons) then { _suspicion = 1; };
				_unit setVariable [UNDERCOVER_SUSPICIOUS, false, true];

				if (time > _timeSeen) then { _unit setVariable ["bSeen", false]; };

				pr _distance = -1;
				if !(isNull _nearestEnemy) then {
					_distance = (position _nearestEnemy) distance (position _unit);

					#ifdef DEBUG 
					_unit setVariable ["nearestEnemyDist", _distance]; 
					#endif
				}; // get distance to nearestEnemy


				0 call { // start exitWith scope

					if (animationState _unit == "ace_amovpercmstpssurwnondnon") exitWith { _suspicion = 0; }; // Hotfix for ACE surrendering
					if ( _unit getVariable ["ACE_isUnconscious", false] ) exitWith { _suspicion = 0; }; 

					/* 
					--------------------------------------------------------------------------------------------------------------------------------------------
					|	W A N T E D   S T A T E 																											   |
					--------------------------------------------------------------------------------------------------------------------------------------------
					*/

					if (UNDERCOVER_IS_UNIT_WANTED(_unit)) exitWith { // start WANTED routine

						// create marker, kind of like GTA's red circle you have to escape to lose the police
						if (_bSeen) then {
							pr _mrkLastHost = createMarkerLocal ["mrkLastHostility", position _unit];
							"mrkLastHostility" setMarkerAlphaLocal 0.0;

							#ifdef DEBUG
								"mrkLastHostility" setMarkerBrushLocal "SOLID";
								"mrkLastHostility" setMarkerAlphaLocal 0.5;
								"mrkLastHostility" setMarkerColorLocal "ColorBlue";
								"mrkLastHostility" setMarkerSizeLocal [WANTED_CIRCLE_RADIUS/2, WANTED_CIRCLE_RADIUS/2];
								"mrkLastHostility" setMarkerShapeLocal "ELLIPSE";
							#endif

							if (_bInVeh && count crew vehicle _unit > 1) then {

								{
									if (isPlayer _x && alive _x) then { _x setVariable [UNDERCOVER_WANTED, true, true]; };
								} forEach crew vehicle _unit;

							}; // sets other units in vehicle wanted

						}; // only update marker if unit is seen, otherwise no escape possible

						_suspicion = 1;

					 	#ifdef DEBUG 
						_unit setVariable ["bInMarker", true]; // debug UI variable
						#endif	

						// conditions for going back to UNDERCOVER state
						if ( ((position _unit) distance2D (getMarkerPos "mrkLastHostility")) > WANTED_CIRCLE_RADIUS) exitWith { _removeWanted = true; };
						if ((_timeSeen - time) < TIME_UNSEEN_WANTED_EXIT) exitWith { _removeWanted = true; };
						if ({alive _x} count units group _nearestEnemy == 0 ) exitWith { _removeWanted = true; }; // no unit from group that last spotted player unit is alive

					}; // end WANTED routine

					/* 
					--------------------------------------------------------------------------------------------------------------------------------------------
					|	 U N D E R C O V E R  S T A T E 																									   |
					--------------------------------------------------------------------------------------------------------------------------------------------
					*/		

					/*
						IN-VEHICLE AND ON FOOT
					*/

				 	if (time < _timeHostility) exitWith { _suspicion = 1; };

				 	if (CALL_STATIC_METHOD("Location", "getLocationAtPos", [_unit]) != "") exitWith { _suspicion = 1; };

					if ( (vehicle _unit nearRoads SUSP_NOROADS) isEqualTo [] ) then { 
						_suspicion = _suspicion + SUSPICIOUS;	
					}; // suspiciousness penalty for being too far from roads

					/*
						END IN-VEHICLE AND ON FOOT
					*/

					switch (_bInVeh) do {

						// player unit is NOT in vehicle
						case false: { 

							_unit setVariable [UNDERCOVER_EXPOSED, true, true];

							pr _suspStance = 0;
							switch (stance _unit) do {
								case "CROUCH": { _suspStance = SUSP_CROUCH; };
					    		case "PRONE": { _suspStance = SUSP_PRONE; };
							}; // stance suspiciousness

							pr _suspSpeed = (vectorMagnitude velocity _unit) * 0.06;
							if ( _suspSpeed > SUSP_SPEEDMAX ) then { _suspSpeed = SUSP_SPEEDMAX; };

							_suspicion = _suspicion + _suspGear + _suspSpeed + _suspStance;

						}; // end case: player unit is NOT in vehicle

						// player unit IS in vehicle
						case true: { 

							_suspicion = 0;
							if !(gettext (configfile >> "CfgVehicles" >> (typeOf vehicle _unit) >> "faction") == "CIV_F") then {
								_suspicion = SUSPICIOUS;
							}; // if in military vehicle

							// Always re-evaluate body exposure while in a vehicle
							pr _bodyExposure = _unit getVariable "bodyExposure";
							pr _eyePosNewVeh = (vehicle _unit) worldToModelVisual (_unit modelToWorldVisual (_unit selectionPosition "head"));
							pr _eyePosOldVeh = _unit getVariable "eyePosOldVeh";
							pr _eyePosOld = _unit getVariable "eyePosOld";

							// bodyExposure and eyePos
							if ((_eyePosOldVeh vectorDistance _eyePosNewVeh) > 0.15) then { 
								_bodyExposure = [20, 120, 0, 360, _unit] call fnc_getVisibleSurface;
								_unit setVariable ["bodyExposure", _bodyExposure]; 

								// Limit body exposure to more usable values, set bExposed variable
								if (_bodyExposure < 0.12) then {
									_bodyExposure = 0.0;
									_unit setVariable [UNDERCOVER_EXPOSED, false, true];

								} else {
									if (_bodyExposure > 0.85) then {
										_bodyExposure = 1;
										_unit setVariable [UNDERCOVER_EXPOSED, true, true];
									};
								};

							}; _unit setVariable ["eyePosOldVeh", _eyePosNewVeh]; // bodyExposure and eyePos

							/* 
								Suspiciousness in a civilian vehicle, based on distance to the nearest enemy who sees player unit
							*/

							// make sure there is an actual enemy and a distance
							if (_distance != -1 && _suspGearVeh >= SUSPICIOUS) then { 
		
								// player unit's gear is suspicious, and player is so close they can see it
								if ( _distance < SUSP_VEH_DIST_MIN && _distance > -1 && _bodyExposure > 0.4 ) exitWith { _suspicion = 1; };
		
								// scale in suspiciousness as player unit gets closer to nearest enemy
								if ( _distance >= SUSP_VEH_DIST_MIN && _distance < SUSP_VEH_DIST && _suspGearVeh >= SUSPICIOUS ) exitWith {
									_suspicion = _suspicion + ( (SUSP_VEH_DIST - _distance) * (1 + _bodyExposure) ) * SUSP_VEH_DIST_MULT; 
								};
							};
						}; // end case: player unit IS in vehicle

						
					}; // end switch "is player unit in vehicle?"

				}; // end exitWith scope

				if (_removeWanted) then { 
					deleteMarkerLocal "mrkLastHostility";
					_unit setVariable [UNDERCOVER_WANTED, false, true];
					_unit setVariable ["removeWanted", false];

					#ifdef DEBUG 
						_unit setVariable ["bInMarker", false]; // debug UI variable
					#endif
				};

				if ( _suspicion >= SUSPICIOUS && _suspicion < 1 ) then { _unit setVariable [UNDERCOVER_SUSPICIOUS, true, true]; };
				if ( _suspicion >= 1 ) then { _unit setCaptive false; } else { _unit setCaptive true; };

				#ifdef DEBUG // set variables for debug GUI
					_unit setVariable ["bInVeh", _bInVeh];
					_unit setVariable ["suspicion", _suspicion];
					_unit setVariable ["timeSeenDebug", (_timeSeen - time)];
					_unit setVariable ["timeHostilityDebug", (_timeHostility - time)];

					/*
					// DEBUG: check # units alive in last group that saw you

					pr _unitsGrpAlive = 0;
					{
						if (alive _x) then { _unitsGrpAlive = _unitsGrpAlive + 1; };
					} forEach units group _nearestEnemy;
					systemChat format ["Units alive in group: %1", _unitsGrpAlive];
					*/
				#endif 
			}; // end SMON_MESSAGE_PROCESS
			
			// called when player unit is being spotted by an enemy group
			case SMON_MESSAGE_BEING_SPOTTED: {

				pr _msgData = _msg select MESSAGE_ID_DATA;
				pr _unit = GETV(_thisObject, "unit");
				pr _suspicion = _unit getVariable "suspicion";
				_unit setVariable ["bSeen", true];
				_unit setVariable ["timeSeen", time + TIME_SEEN];

				// Below: find enemy unit closest to player unit and store it in variable for SMON_MESSAGE_PROCESS
				pr _grpDistances = [];

				{
					pr _tempDist = (position _x) distance (position _unit);
					_grpDistances pushBack _tempDist;
				} forEach units _msgData;

				pr _minDist = selectMin _grpDistances;
				pr _minDistIndex = _grpDistances find _minDist;

				pr _nearestEnemy = (units _msgData) select _minDistIndex;
				_unit setVariable ["nearestEnemy", _nearestEnemy];

				if (_suspicion >= 1) then { 
					 _unit setVariable [UNDERCOVER_WANTED, true, true];
				}; // end SMON_MESSAGE_BEING_SPOTTED
			};

			case SMON_MESSAGE_COMPROMISED: {
			
				pr _unit = GETV(_thisObject, "unit");
				_unit setVariable [UNDERCOVER_WANTED, true, true];	

			}; // end SMON_MESSAGE_COMPROMISED
		};
		
		false
	} ENDMETHOD;
	
	// SensorGroupTargets remoteExecutes this on player's computer when a group is currently spotting player
	// This function resolves UndercoverMonitor of player and posts a message to it
	STATIC_METHOD("onUnitSpotted") {
		params ["_thisClass", ["_unit", objNull, [objNull]], ["_group", grpNull, [grpNull]]];
		pr _um = _unit getVariable ["undercoverMonitor", ""];
		if (_um != "") then { // Sanity check
			pr _msg = MESSAGE_NEW();
			MESSAGE_SET_TYPE(_msg, SMON_MESSAGE_BEING_SPOTTED);
			MESSAGE_SET_DATA(_msg, _group);
			CALLM1(_um, "postMessage", _msg);
		};
	} ENDMETHOD;

ENDCLASS;
