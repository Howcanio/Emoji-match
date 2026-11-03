# Manual QA checklist (physical iPhone)

Automated tests cover rules and flows on simulators. Everything here needs a person and a real device, because simulators have no haptics and can't judge feel, audio, or frame pacing.

**None of this has been performed yet.** Record the device, iOS version, build, and tester when you run it.

Device: ________ iOS: ________ Build: ________ Tester: ________ Date: ________

## Launch and navigation

- [ ] Icon and "Emoji Match" name look right on the Home Screen
- [ ] Launch shows the cream launch color with no white flash, then Home
- [ ] Home shows logo, tagline, Play, best score, and settings gear
- [ ] App stays portrait when the device is rotated
- [ ] Nothing collides with the Dynamic Island, notch, or home indicator

## Gestures

- [ ] Touching an emoji lights it up and scales it, with a light haptic
- [ ] Dragging draws a glowing string from the tile to the finger
- [ ] Nonmatching emojis dim and are ignored when crossed
- [ ] Matching emojis out of reach dim and aren't selected
- [ ] The gauge above the board shrinks as string is used
- [ ] The string goes taut at its limit rather than following the finger further
- [ ] Reaching the third tile pops immediately, without lifting
- [ ] After a match, continuing to drag does nothing until you lift
- [ ] Lifting with one or two tiles selected clears the selection with no score
- [ ] All eight directions work, including diagonals
- [ ] Skipping across other emojis to a distant match works
- [ ] A very fast flick over matching tiles selects them in order
- [ ] Dragging off the board edge and back keeps the selection
- [ ] A second finger placed mid-drag doesn't disturb the first
- [ ] Touching a new tile right after a match, during the animation, starts a selection promptly

## Feel and animation

- [ ] Pop is snappy (about 180 ms), with sparks and a floating +100
- [ ] Tiles fall smoothly with a small landing squash; new tiles enter from the top
- [ ] No hitches over 60 seconds of rapid play, on the oldest supported device you have
- [ ] Battery and heat are reasonable after five consecutive rounds

## Sound and haptics

- [ ] Selection blips, match pop, final-five-second ticks, and end chime are pleasant and not too loud
- [ ] Silent switch mutes all game audio
- [ ] Music from another app keeps playing and mixes with game sound
- [ ] Sound off in Settings silences everything, after relaunch too
- [ ] Haptics off in Settings stops all haptics, after relaunch too
- [ ] Select haptic is gentle; match haptic is clearly stronger

## Timer and interruptions

- [ ] Timer starts at 60 after the short board intro, and turns red at 10
- [ ] Round ends at 0 with "Time's up!", then results
- [ ] A gesture in progress at 0 is cancelled and doesn't score
- [ ] A match landed just before 0 still counts
- [ ] Home Screen swipe mid-round: timer freezes, and resumes on return
- [ ] Lock and unlock mid-round: same
- [ ] Incoming call or alarm mid-round: timer pauses; sound recovers afterward
- [ ] Control Center and Notification Center pulled down mid-drag: selection clears, timer pauses, play resumes cleanly
- [ ] Backgrounding during a pop animation: board is correct on return

## Results and persistence

- [ ] Results show final score, personal best, matches, Play Again, and Home
- [ ] A record shows "New best!" and plays the fanfare
- [ ] Play Again starts a fresh 60 seconds with a new board and score 0
- [ ] Best score survives force-quit and device restart
- [ ] Works in Airplane Mode

## Accessibility

- [ ] Reduce Motion: no scaling, sparks, falling, or squash; tiles fade; play remains clear
- [ ] Largest Dynamic Type: Home, HUD, Results, and Settings remain usable
- [ ] VoiceOver reads Home, HUD, Results, and Settings controls sensibly (board isn't playable; known limitation)
- [ ] Emojis remain distinguishable with color filters on

## Sizes (as available)

- [ ] Small: iPhone SE or 16e class
- [ ] Standard: iPhone 15/16/17
- [ ] Large: Pro Max class
