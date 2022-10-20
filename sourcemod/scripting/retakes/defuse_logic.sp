/*
 * • Mainly acts as an instant defuse script.
 *
 * • Retake is a game mode where players get bored real quick if things
 * 	 move too slow, therefore we want to preserve as much as time possible.
 *
 * • Defuse logic is responsible for allowing attackers to instantly defuse
 * 	 the planted c4, when meeting the required conditions.
 *
 * • Required conditions to instantly defuse a planted c4:
 *		1. There is enough time to defuse the bomb. (5.0s using defuse kit, 10.0s without)
 * 		2. Zero defenders alive.
 * 		3. No molotov near the planted c4.
 */

#assert defined COMPILING_FROM_MAIN