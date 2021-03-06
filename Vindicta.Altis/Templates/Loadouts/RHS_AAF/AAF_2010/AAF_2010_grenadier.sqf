removeAllWeapons this;
removeAllItems this;
removeAllAssignedItems this;
removeUniform this;
removeVest this;
removeBackpack this;
removeHeadgear this;
removeGoggles this;

_RandomHeadgear = selectRandom ["FGN_AAF_Cap_Lizard","FGN_AAF_PASGT_Lizard","FGN_AAF_PASGT_Lizard_ESS","FGN_AAF_PASGT_Lizard_ESS_2","rhsgref_helmet_pasgt_olive"];
this addHeadgear _RandomHeadgear;
_RandomGoggles = selectRandom ["FGN_AAF_Shemag_tan","FGN_AAF_Shemag","rhs_scarf","","",""];
this addGoggles _RandomGoggles;
this forceAddUniform "FGN_AAF_M93_Lizard";
_RandomVest = selectRandom ["FGN_AAF_M99Vest_Lizard_Rifleman","FGN_AAF_M99Vest_Khaki_Rifleman"];
this addVest _RandomVest;
this addBackpack "B_LegStrapBag_coyote_F";

this addWeapon "rhs_weap_akm_gp25";
this addPrimaryWeaponItem "rhs_acc_dtkakm";
this addPrimaryWeaponItem "rhs_VOG25";
this addPrimaryWeaponItem "rhs_30Rnd_762x39mm";

this addItemToUniform "FirstAidKit";
for "_i" from 1 to 4 do {this addItemToVest "rhs_30Rnd_762x39mm";};
for "_i" from 1 to 2 do {this addItemToVest "rhs_grenade_mkii_mag";};
for "_i" from 1 to 2 do {this addItemToBackpack "rhs_VG40MD";};
this addItemToBackpack "rhs_GRD40_Green";
this addItemToBackpack "rhs_GRD40_Red";
for "_i" from 1 to 6 do {this addItemToBackpack "rhs_VOG25";};
this addItemToBackpack "rhs_VG40OP_red";
for "_i" from 1 to 4 do {this addItemToBackpack "rhs_VG40OP_white";};
this addItemToBackpack "rhs_VG40OP_green";
for "_i" from 1 to 2 do {this addItemToBackpack "rhs_VOG25P";};
this linkItem "ItemWatch";