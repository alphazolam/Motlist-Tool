-- MOTLIST TOOL
/*
	Script Author: 	alphaZomega
	Release Date: 	Dec 6 2020
	Latest Update:	March 24, 2023
	Version: 		0.85
	
	Visit https://residentevilmodding.boards.net/thread/14132/motlist-maxscript-custom-animations-engine for updates
*/

(
	version = 85
	global motlistMod
	global SelectAnim

	fn GetMultiOpenFilenames caption:"Open" filename:"" types:"All Files (*.*)|*.*" default:1 = ( --thanks to Che
		local dlg = DotNetObject "System.Windows.Forms.OpenFileDialog"
		dlg.multiSelect = true
		dlg.title = caption
		
		local p = getFilenamePath filename
		if doesFileExist p then
			dlg.initialDirectory = p
		if types == "|" then
			dlg.filter = (substring types 1 (types.count - 1))
		else
			dlg.filter = types
		
		dlg.filterIndex = default
		
		local result = dlg.ShowDialog()
		if (result.Equals result.OK) then
			dlg.filenames[1] --only need one file here
		else
			undefined
	)
	
	fn isUselessController cnt = (
		return false
		return (numkeys cnt == 2 and getkeytime cnt 1 == -0.0125 and getkeytime cnt 2 == 0)
	)

	fn GetStartEndKeys obj type inputInterval = (
		
		controller = obj.controller[type].controller
		if controller == undefined or controller.keys == undefined then
			controller = obj.controller[4][type].controller --for IK
		
		local keys = for key in controller.keys where key.time >= inputInterval.start and key.time <= inputInterval.end collect key
		
		if keys.count < 1 then ( format "% % \n" keys.count obj.name; return undefined )
		timeRange = (interval keys[1].time keys[keys.count-1].time)
		if controller.numsubs == 3 then ( --Bezier_Float controllers
			local subIntervals = #()
			for c = 1 to controller.numsubs do (
				local test = GetKeyIndex controller[c].controller timeRange.start; if test > 0 then append subIntervals test
				test = GetKeyIndex controller[c].controller timeRange.end; if test > 0 then append subIntervals test
			)
			if subIntervals.count == 0 then return undefined
			local idxRange =  (interval (amin subIntervals) (amax subIntervals))
		) else 
			local idxRange =  (interval (GetKeyIndex controller timeRange.start) (GetKeyIndex controller timeRange.end))
		return #(timeRange, idxRange, keys) 
	)

	--with undo on ( for bone in selection as array do ( i = findstring bone.name "LOD0_"; if i != undefined then bone.name = replace bone.name i 5 "" ) )
		
	struct motBoneHeader
	(
		address,
		boneNameOffs,
		parentOffs,
		childOffs,
		nextSiblingOffs,
		translation,
		quaternion,
		Index,
		boneHash,
		padding,
		boneName
	)

	fn writeMotBoneHeader &bstream input = 
	(
		writelonglong bstream input.boneNameOffs #unsigned
		writelonglong bstream input.parentOffs #unsigned
		writelonglong bstream input.childOffs #unsigned
		writelonglong bstream input.nextSiblingOffs #unsigned
		writefloat bstream input.translation.x
		writefloat bstream input.translation.y
		writefloat bstream input.translation.z
		writefloat bstream 0
		writefloat bstream input.quaternion.x
		writefloat bstream input.quaternion.y
		writefloat bstream input.quaternion.z
		writefloat bstream input.quaternion.w
		writelong bstream input.Index #unsigned
		writelong bstream input.boneHash #unsigned
		writelonglong bstream input.padding #unsigned
	)

	fn ReadFixedString &bstream fixedLen =
	(
		local str = ""
		local length = 0 
		try (
			for s = 1 to fixedLen do
			(
				local c = (readshort bstream) as integer
				if c == 0 then exit
				fseek bstream -2 #seek_cur
				local d = readbyte bstream
				if d == 0 then continue 
				str += bit.intAsChar(d) 
				if d != 32 then length = s		
			)
		) catch ( print "Error reading string" )
		substring str 1 length
	)

	fn readMotBoneHeader &bstream start = 
	(
		local Info = motBoneHeader()
		Info.address = ftell bstream
		Info.boneNameOffs = readlonglong bstream #unsigned
		Info.parentOffs = readlonglong bstream #unsigned
		Info.childOffs = readlonglong bstream #unsigned
		Info.nextSiblingOffs = readlonglong bstream #unsigned
		Info.translation = (point4 (readfloat bstream) (readfloat bstream) (readfloat bstream) (readfloat bstream))
		Info.quaternion = (quat (readfloat bstream) (readfloat bstream) (readfloat bstream) (readfloat bstream))
		Info.Index = readlong bstream #unsigned 
		Info.boneHash = (readlong bstream #unsigned)
		Info.padding = readlonglong bstream #unsigned
		fseek bstream (Info.boneNameOffs+start) #seek_set
		--If you are reading this, just restart the script!!!
		Info.boneName = ReadFixedString bstream 128 
		fseek bstream ( Info.address + 80 ) #seek_set
		Info
	)


	struct header
	(
		version,
		magic,
		padding,
		pointersOffs,
		colOffs,
		motlistNameOffs,
		padding2,
		numOffs
	)

	fn readHeader &bstream = 
	(
		local Info = header()
		Info.version = readlong bstream #unsigned
		Info.magic = readlong bstream #unsigned
		Info.padding = readlonglong bstream #unsigned
		Info.pointersOffs = readlonglong bstream #unsigned
		Info.colOffs = readlonglong bstream #unsigned
		Info.motlistNameOffs = readlonglong bstream #unsigned
		if version != 60 then Info.padding2 = readlonglong bstream #unsigned
		Info.numOffs = readlong bstream #unsigned
		Info
	)

	struct trackHdrRE2 
	(
		address,
		flags,
		keyCount,
		frameRate,
		maxFrame,
		frameIndOffs,
		frameDataOffs,
		unpackDataOffs,
		lowestOffs,
		type
	)

	fn readTrackHdrRE2 &bstream type = ( 
		local Info = trackHdrRE2()
		Info.address = ftell bstream
		Info.flags = readlong bstream #unsigned
		Info.keyCount = readlong bstream #unsigned
		Info.frameRate = readlong bstream #unsigned
		Info.maxFrame = readfloat bstream
		Info.frameIndOffs = readlonglong bstream #unsigned
		Info.frameDataOffs = readlonglong bstream #unsigned
		Info.unpackDataOffs = readlonglong bstream #unsigned 
		Info.lowestOffs = Info.frameIndOffs
		if Info.lowestOffs == 0 then Info.lowestOffs = Info.frameDataOffs
		Info.type = type
		Info
	)

	struct trackHdrRE3 
	(
		address,
		flags,
		keyCount,
		frameIndOffs,
		frameDataOffs,
		unpackDataOffs,
		lowestOffs,
		type
	)

	fn readTrackHdrRE3 &bstream type = 
	( 
		local Info = trackHdrRE3()
		Info.address = ftell bstream
		Info.flags = readlong bstream #unsigned
		Info.keyCount = readlong bstream #unsigned
		Info.frameIndOffs = readlong bstream #unsigned
		Info.frameDataOffs = readlong bstream #unsigned
		Info.unpackDataOffs = readlong bstream #unsigned 
		Info.lowestOffs = Info.frameIndOffs
		if Info.lowestOffs == 0 then Info.lowestOffs = Info.frameDataOffs
		Info.type = type
		Info
	)

	fn writeTrackHeader &bstream input = 
	(
		writelong bstream input.flags #unsigned
		writelong bstream (input.keyCount) #unsigned
		if version == 85 or version == 60 then ( --RE2 and RE7
			writelong bstream input.frameRate #unsigned
			writefloat bstream input.maxFrame
			writelonglong bstream input.frameIndOffs #unsigned
			writelonglong bstream input.frameDataOffs #unsigned
			writelonglong bstream input.unpackDataOffs #unsigned
		) else if version == 99 or version == 486 then ( --RE3 / RE8
			writelong bstream input.frameIndOffs #unsigned
			writelong bstream input.frameDataOffs #unsigned
			writelong bstream input.unpackDataOffs #unsigned
		)
	)

	struct BoneClipHdrRE2 
	(
		address,
		boneIndex,
		trackFlags1,
		trackFlags2,
		boneHash,
		uknFloat,
		padding,
		trackHdrOffs
	)

	fn readBoneClipHdrRE2 &bstream = ( 
		local Info = BoneClipHdrRE2()
		Info.address = ftell bstream
		Info.boneIndex = readshort bstream #unsigned
		Info.trackFlags1 = readbyte bstream
		Info.trackFlags2 = readbyte bstream
		Info.boneHash = (readlong bstream #unsigned)
		Info.uknFloat = readfloat bstream
		Info.padding = readlong bstream
		Info.trackHdrOffs = readlonglong bstream #unsigned
		Info
	)

	fn writeBoneClipHeader &bstream input = 
	(
		writeshort bstream input.boneIndex
		writebyte bstream input.trackFlags1
		writebyte bstream input.trackFlags2
		writelong bstream input.boneHash #unsigned
		if version == 85 then ( --RE2
			writefloat bstream input.uknFloat
			writelong bstream input.padding
			writelonglong bstream input.trackHdrOffs
		) else if version == 60 then writelonglong bstream input.trackHdrOffs #unsigned --RE7
		else writelong bstream input.trackHdrOffs #unsigned --RE3 / REV
	)

	struct BoneClipHdrRE3 
	(
		address,
		boneIndex,
		trackFlags1,
		trackFlags2,
		boneHash,
		trackHdrOffs
	)

	fn readBoneClipHdrRE3 &bstream =  --also for RE7
	( 
		local Info = BoneClipHdrRE3()
		Info.address = ftell bstream
		Info.boneIndex = readshort bstream #unsigned
		Info.trackFlags1 = readbyte bstream
		Info.trackFlags2 = readbyte bstream
		Info.boneHash = (readlong bstream #unsigned)
		if version == 60 then Info.trackHdrOffs = readlonglong bstream #unsigned --RE7
		else Info.trackHdrOffs = readlong bstream #unsigned --RE3
		Info
	)

	struct MotionHeader 
	(
		Version,
		Magic,
		unknown,
		motSize,
		offsToBoneHdrOffs,
		boneClipHdrOffs,
		clipFileOffset,
		Offs1,
		Offs2,
		namesOffs,
		frameCount,
		blending,
		uknFloat1,
		uknFloat2,
		boneCount,
		boneClipCount,
		uknPointer2Count,
		uknPointer3Count,
		frameRate,
		uknPointerCount,
		uknShort2
	)

	fn readMotionHeader &bstream = 
	(
		local Info = MotionHeader()
		Info.Version = readlong bstream
		Info.Magic = readlong bstream
		Info.unknown = readlong bstream
		Info.motSize = readlong bstream
		Info.offsToBoneHdrOffs = readlonglong bstream
		Info.boneClipHdrOffs = readlonglong bstream
		readlonglong bstream; readlonglong bstream
		Info.clipFileOffset = readlonglong bstream
		Info.Offs1 = readlonglong bstream
		readlonglong bstream
		if Info.Version >= 456 then 
			readlonglong bstream
		Info.Offs2 = readlonglong bstream
		Info.namesOffs = readlonglong bstream
		Info.frameCount = readfloat bstream
		Info.blending = readfloat bstream
		Info.uknFloat1 = readfloat bstream
		Info.uknFloat2 = readfloat bstream
		Info.boneCount = readshort bstream #unsigned
		Info.boneClipCount = readshort bstream #unsigned
		Info.uknPointer2Count = readbyte bstream #unsigned
		Info.uknPointer3Count = readbyte bstream #unsigned
		Info.frameRate = readshort bstream #unsigned
		Info.uknPointerCount = readshort bstream #unsigned
		Info.uknShort2 = readshort bstream #unsigned
		Info
	)

	fn ReadLongAtOffset bstream offset = (
		local pos = ftell bstream
		fseek bstream offset #seek_set
		local Info = readlong bstream #unsigned
		if Info == undefined then Info = 0
		fseek bstream pos #seek_set
		Info
	)

	fn findNextOfLong &bstream searchFrom searchFor = 
	(
		local pos = ftell bstream
		fseek bstream searchFrom #seek_set
		while mod (ftell bstream) 4 != 0 do (fseek bstream 2 #seek_cur)
		local tester = readlong bstream  #unsigned
		while tester != searchFor  do ( 
			tester = readlong bstream #unsigned
			if tester == undefined then exit --stop at end of file
		)
		fseek bstream -4 #seek_cur
		offset = ftell bstream
		if offset == undefined then ( fseek bstream 0 #seek_end; offset = ftell bstream )
		fseek bstream pos #seek_set
		offset
	)

	fn readLongAt bstream pos = 
	(
		local returnPos = ftell bstream
		fseek bstream pos #seek_set
		local long = readlong bstream
		fseek bstream returnPos #seek_set
		long
	)

	fn padToNextLine bstream = 
	(
		while mod (ftell bstream) 16 != 0 do writebyte bstream 0
	)

	fn hasValidParent node = 
	(
		local value = false
		if node.parent != undefined then if node.parent.isSelected then value = true
		--if node.parent != undefined then value = true
		value
	)

	fn getRoot node = --get top most parent node
	( 
		while hasValidParent node do node = node.parent;
		node
	)

	fn getSiblings node = 
	(
		local siblings = #()
		if node.parent != undefined then for s in node.parent.children do if s.isSelected then append siblings s
		siblings
	)

	fn breadthFirstSearch node = 
	(
		local tmpArr = #(node)
		for c in node.children do if c.isSelected then
		(
			append tmpArr c
			join tmpArr (getSiblings c)		
		)
		for c = 0 to node.children.count-1 do
			if node.children[node.children.count-c].isSelected then
			(
				append tmpArr node.children[node.children.count-c]
				join tmpArr (breadthFirstSearch node.children[node.children.count-c])		
			)
		makeUniqueArray tmpArr
		tmpArr
	)

	fn reverseArray arr = (
		local newArr = for i=arr.count to 1 by -1 collect arr[i]
		newArr
	)

	fn calcQuatW quaternion = 
	(
		local RotationW = 1.0 - (quaternion.x * quaternion.x + quaternion.y * quaternion.y + quaternion.z * quaternion.z)
		if RotationW > 0 then RotationW = sqrt RotationW
		else RotationW = 0
		RotationW
	)

	fn generate_hash key isWString seed:0xFFFFFFFFL = --generates a murmur3 hash from a string
	(
		fn fmix h  seed:0xFFFFFFFFL =  --RE Engine seed is always 0xFFFFFFFF or 4294967295
		(
			h = bit.xor h (bit.shift h -16)
			h = bit.and (h * 0x85ebca6bL) seed
			h = bit.xor h (bit.shift h -13)
			h = bit.and (h * 0xc2b2ae35L) seed
			h = bit.xor h (bit.shift h -16)
			h
		)	
		local newKey = #(); 
		for i = 1 to key.count do ( 
			append newKey ((bit.charAsInt key[i]) as integer64)
			if isWString != 0 then append newKey 0L 
		)
		key = newKey
		local length = key.count as integer64
		local nBlocks = (length / 4) as integer64
		local h1 = seed 
		local c1 = 0xcc9e2d51L
		local c2 = 0x1b873593L		
		for block_start = 1 to (nblocks * 4) by 4 do ( 
			k1 = bit.or (bit.or (bit.or (bit.shift key[block_start + 3] 24) (bit.shift key[block_start + 2] 16)) (bit.shift key[block_start + 1] 8)) (key[block_start + 0])
			k1 = bit.and (c1 * k1) seed
			k1 = bit.and (bit.or (bit.shift k1 15) (bit.shift k1 -17)) seed
			k1 = bit.and (c2 * k1) seed
			h1 = bit.xor h1 k1
			h1 = bit.and (bit.or (bit.shift h1 13) (bit.shift h1 -19)) seed
			h1 = bit.and (h1 * 5 + 0xe6546b64L) seed
		)	
		local tail_index = (nblocks * 4) + 1; k1 = 0
		local tail_size = bit.and length 3
		if tail_size >= 3 then k1 = bit.xor k1 (bit.shift key[tail_index + 2] 16)
		if tail_size >= 2 then k1 = bit.xor k1 (bit.shift key[tail_index + 1] 8)
		if tail_size >= 1 then k1 = bit.xor k1 (key[tail_index + 0])
		if tail_size > 0 then (
			k1 = bit.and (k1 * c1) seed
			k1 = bit.and (bit.or (bit.shift k1 15) (bit.shift k1 -17)) seed
			k1 = bit.and (k1 * c2) seed
			h1 = bit.xor h1 k1
		)
		local unsigned_val = fmix (bit.xor h1 length)
		if (bit.and unsigned_val 0x80000000L) == 0 then 
			return unsigned_val
		else
			return -((bit.xor unsigned_val seed) + 1)
	)

	fn writeUnicodeString &bstream input = (
		for char = 1 to input.count do (
			writeByte bstream (bit.charAsInt input[char]) #unsigned
			writebyte bstream 0
		)
		writeshort bstream 0
	)

	--function to create bone headers and write them to the file, used at different times for RE7/RE2/DMC5 and RE3/RE8:
	fn packAndwriteMotBoneHeaders &f &nf objSelected motBoneHeaders mHeader start animScale firstFrame  = (
		
		local boneHdrOffs = (ftell nf + 16)
		writelonglong nf (boneHdrOffs - start) #unsigned --boneHdrOffs
		writelonglong nf (objSelected.count) #unsigned --boneHdrCount
		fseek nf (start+16) #seek_set --OffsToboneHdrOffs
		writelonglong nf (boneHdrOffs - 16 - start) #unsigned
		fseek nf boneHdrOffs #seek_set
		
		local newBoneHeaders = #()
		local namesStart = (ftell nf) + objSelected.count * 80
		local bnHdrStart = ftell nf
		
		--prepare bone headers
		for i = 1 to objSelected.count do (
			local bnHdr = motBoneHeader()
			bnHdr.address = bnHdrStart + (i-1) * 80
			bnHdr.boneNameOffs = (namesStart - start)
			local parentIdx = -1
			if hasValidParent objSelected[i] then (
				for j = 1 to objSelected.count do if objSelected[j] == objSelected[i].parent then (parentIdx = j-1 ; exit )
				if parentIdx != -1 then bnHdr.parentOffs = boneHdrOffs + 80 * parentIdx - start
				else bnHdr.parentOffs = 0
			) else ( 
				bnHdr.parentOffs = 0
				local rootBone = objSelected[i]
			)
			local childIdx = -1
			for j = 1 to objSelected.count do 
				if objSelected[i] == objSelected[j].parent then (childIdx = j-1; exit )
			if childIdx != -1 then bnHdr.childOffs = boneHdrOffs + 80 * childIdx - start
			else bnHdr.childOffs = 0
			
			local siblingIdx = -1
			if hasValidParent objSelected[i] then (
				for j = 1 to objSelected.count do 
					if hasValidParent objSelected[j] then 
						if objSelected[i] != objSelected[j] and objSelected[i].parent == objSelected[j].parent and boneHdrOffs + 80 * (i-1) < boneHdrOffs + 80 * (j-1) then (siblingIdx = j-1; exit )
				if siblingIdx != -1 then bnHdr.nextSiblingOffs = boneHdrOffs + 80 * siblingIdx - start
				else bnHdr.nextSiblingOffs = 0
			) else bnHdr.nextSiblingOffs = 0
			
			with animate on (
				at time -999999 (
					if hasValidParent objSelected[i] then (
						bnHdr.translation = (point4 (objSelected[i].pos.controller.value.x * animScale) (objSelected[i].pos.controller.value.y * animScale) (objSelected[i].pos.controller.value.z * animScale) 0) 
						if objSelected[i].rotation.controller.value.w < 0 then bnHdr.quaternion = objSelected[i].rotation.controller.value
						else bnHdr.quaternion = inverse objSelected[i].rotation.controller.value
						
					) else ( 
						bnHdr.translation = (point4 (objSelected[i].pos.controller.value.x * animScale) (objSelected[i].pos.controller.value.z * animScale) -(objSelected[i].pos.controller.value.y * animScale) 0) 
						if objSelected[i].rotation.controller.value.w < 0 then bnHdr.quaternion = (objSelected[i].transform.controller.value * (matrix3 [1,0,0][0,0,-1][0,1,0][0,0,0])).rotation
						else bnHdr.quaternion = inverse ((objSelected[i].transform.controller.value * (matrix3 [1,0,0][0,0,-1][0,1,0][0,0,0]))).rotation
					)
				)
			)
			
			bnHdr.Index = i-1
			bnHdr.boneHash = (getuserprop objSelected[i] "BoneHash")
			bnHdr.padding = 0
			bnHdr.boneName = objSelected[i].name
			
			append newBoneHeaders bnHdr
			namesStart += objSelected[i].name.count * 2 + 2
			bnHdrStart += 80 
		)
		--write bone headers
		for i = 1 to newBoneHeaders.count do writeMotBoneHeader nf newBoneHeaders[i]
		--write name strings
		for i = 1 to newBoneHeaders.count do writeUnicodeString nf newBoneHeaders[i].boneName
		padToNextLine nf --padding
		
		return newBoneHeaders
	)

	fn openMotlist file forcedScale startTime stopTime doScale:false doOptimize:false doForceScale:false doStartTime:false doStopTime:false doDisableClip:false = 
	(	
		if file != undefined then (		
			fpath = getFilenamePath file
			fname = getFilenameFile (getFilenameFile file)
			fext = substring file (fpath.count + fname.count + 1) -1
			global newfileName = fpath + fname + ".NEW" + fext
			newFileName = substitutestring newFileName ".ORIG.NEW" ""
			global fileName = file
			global animItems = #()
			local f = fopen file "rb"
			version = readlong f
			magic = readlong f
			
			pointers = #()
			local realVersion = undefined
			if version >= 484 or version == 524 or version == 528 then (
				realVersion = version
				version = 486
			)
			
			if magic == 1953721453 and (version == 60 or version == 85 or version == 99 or version == 486) then ( -- 
				
				--read file header:
				fseek f 0 #seek_set
				local fHeaderFirst = readHeader f
				
				fseek f fHeaderFirst.motlistNameOffs #seek_set
				fseek f fHeaderFirst.pointersOffs #seek_set
				
				local revSkip = 0; if version == 486 then revSkip = 8
				
				--gather pointers and pointer names:
				for i = 1 to fHeaderFirst.numOffs do 
					append pointers (readlonglong f #unsigned)
				for i = 1 to fHeaderFirst.numOffs do (
					
					--fseek f (pointers[i] + 116 + revSkip) #seek_set
					fseek f (pointers[i] + 4) #seek_set
					local magic = readlong f
					if magic == 1701999725 then ( --mtre
						fseek f (pointers[i] + 48) #seek_set
						fseek f (pointers[i] + (readLongLong f)) #seek_set
						local msg = "(MTRE) " + (ReadFixedString f 128)
					) else (
						fseek f (pointers[i] + 80 + revSkip) #seek_set
						local nameOffs = (readLongLong f)
						if nameOffs > 0 then (
							fseek f (pointers[i] + nameOffs) #seek_set
							local msg = (ReadFixedString f 128)
						) else (
							local frames = (readfloat f) as integer
							local msg = "Unnamed (" + (frames as string) + " Frames)"
						)
					)
					
					--	fseek f (pointers[i] + 80 + revSkip) #seek_set
					--	fseek f (pointers[i] + (readLongLong f)) #seek_set
					--	local msg = (ReadFixedString f 128)
					
					if pointers[i] != 0 then 
						append animItems (((i-1) as string) + ". " + msg)
					else 
						append animItems (((i-1) as string) + ". [NULL]")
				)
				
				--open new rollout window to pick mot: /**/
				global currentItem = animItems[1]
				rollout SelectAnim "Select MOT" (
					local currentItemIdx = 1
					local swapItemIdx = 1
					local doScale = doScale; local doOptimize = doOptimize; local doForceScale = doForceScale; local forcedScale = forcedScale
					local doStartTime = doStartTime; local startTime = startTime; local doStopTime = doStopTime; local stopTime = stopTime; local doDisableClip = doDisableClip
					
					group "Select Animation" (
						dropdownlist animSelection "" items:animItems
						button ExportButton "INJECT ANIMATION"
							toolTip:"Saves animation to motlist. Creates modified copy from source motlist file. \n           *DOES NOT MODIFY SOURCE FILE*"
						button RepeatButton "Enable/Disable Repeating"
							toolTip:"Changes the selected mot animation to be repeating or not-repeating without exporting any animation data"
					)
					group "Import Bones" (
						button ImportPositionsButton "Import Bone Positions"
							toolTip:"Modifies the selected bones to match those of the selected mot"
						label blank ""
						checkbox Chk_TPose "T-Pose" checked:false offset:[50, -20]
							toolTip:"Puts the selected bones in a T-pose"
						checkbox Chk_ImportPositions "Positions" checked:true offset:[110, -20]
							toolTip:"Imports bone positions from the selected mot; retargets the size of an animation"
						checkbox Chk_ImportRotations "Rotations" checked:false offset:[180, -20]
							toolTip:"Imports bone rotations from the selected mot; poses the animation "
					)
					button SwapButton "Swap Mot" offset:[-50, 0]
						toolTip:"Moves the bytes of the selected MOT to the end of the file, preventing certain crashes\n RIGHT CLICK on this button to have the swapped mot take the place of an existing mot"
					label MotToSwap "Swap over: [Swap to End]" offset:[50, -22]
					
					on animSelection selected i do (
						currentItem = animSelection.items[i]
						currentItemIdx = i
					)
					
					on SwapButton rightclick do ( 
						MotToSwap.caption = "Swap over: " + animItems[currentItemIdx]
						swapItemIdx = currentItemIdx
					)
					
					on SwapButton pressed do (
						local f = fopen fileName "rb"
						local fileSize = getFileSize fileName
						local pointers = #()
						local fHeader = readHeader f
						version = fHeader.Version
						if version >= 484 then
							version = 486
						if version != 85 and version != 99 and version != 60 and version != 486 then ( 
							messageBox "Unsupported motlist version!"; fclose f; return false 
						)
						fseek f fHeader.pointersOffs #seek_set
						for j = 1 to fHeader.numOffs do 
							append pointers (readlonglong f)
						local start = pointers[currentItemIdx]
						fseek f start #seek_set
						local mHeader = readMotionHeader f
						local nextMotPos = (findNextOfLong f (ftell f) 544501613) - 4 --'mot '
						if start < fHeader.colOffs and nextMotPos > fHeader.colOffs then 
							nextMotPos = fHeader.colOffs
							
						local nf = fopen newfileName "wb"
						fseek nf 0 #seek_set; fseek f 0 #seek_set 
						for short = 1 to fileSize / 2 do 
							writeshort nf (readshort f) --copy file to new file
						
						fseek f start #seek_set
						for short = 1 to (nextMotPos - start) / 2 do 
							writeshort nf (readshort f) --copy swapped mot to end of new file
						
						if MotToSwap.caption == "Swap over: [Swap to End]" then 
							fseek nf (fHeader.pointersOffs + ((currentItemIdx-1) * 8)) #seek_set
						else 
							fseek nf (fHeader.pointersOffs + ((swapItemIdx-1) * 8)) #seek_set
							
						writelonglong nf fileSize --change pointer for that mot to be the old end-of-file
						fclose f
						fclose nf
						local msg = ""
						if MotToSwap.caption == "" then 
							msg = ("Mot:\n" + animItems[currentItemIdx] + "\nswapped to end of file!")
						else 
							msg = ("Mot:\n" + animItems[currentItemIdx] + "\nswapped to end of file")
						if MotToSwap.caption != "Swap over: [Swap to End]" then 
							msg = (msg + ", replacing\n" + animItems[swapItemIdx] + "!")
						messagebox msg
						destroydialog SelectAnim
					)
					
					on RepeatButton pressed do (
						local f = fopen fileName "r+"
						local fHeader = readHeader f
						local pointers = #()

						fseek f fHeader.pointersOffs #seek_set
						for j = 1 to fHeader.numOffs do ( append pointers (readlong f); fseek f 4 #seek_cur )
						fseek f pointers[currentItemIdx] #seek_set
						local mHeader = readMotionHeader f
						if mHeader.magic != 544501613 then ( --mot
							messagebox "Not supported"; fclose f; return 0
						)
						
						fseek f (pointers[currentItemIdx]+92) #seek_set
						if ( queryBox "Are you sure you want to modify the motlist file?" title:"Change looping") == true do (
							if mHeader.blending == -1 then (
								writefloat f 0
								local message = "Changed mot " + animItems[currentItemIdx] + " to be repeating!"
							) else if mHeader.blending == 0 then (
								writefloat f -1
								local message = "Changed mot " + animItems[currentItemIdx] + " to be non-repeating!"  
							)
						)
						fclose f
						messageBox message; destroydialog SelectAnim
						return true
					)
					
					on ImportPositionsButton rightclick do (
						local objSelected = selection as array
						for p in objSelected where superclassof p == GeometryClass and p.children != undefined do join objSelected p.children
						for i = 1 to objSelected.count do objSelected[i].boneScaleType = #none
						print "Removed bone scale"
					)
					
					on ImportPositionsButton pressed do (
						local f = fopen fileName "rb"
						--local objSelected = reverseArray (selection as array)
						local fileSize = getFileSize fileName
						local pointers = #()
						local fHeader = readHeader f

						boneScale = 1
						if doScale == true then boneScale = 100
						version = fHeader.Version
						if version >= 484  then
							version = 486
						if version != 85 and version != 99 and version != 60 and version != 486 then ( messageBox "Unsupported motlist version!"; fclose f; return false )
						
						fseek f fHeader.pointersOffs #seek_set
						for j = 1 to fHeader.numOffs do ( append pointers (readlonglong f) )
						
						local start = pointers[currentItemIdx]
						fseek f start #seek_set
						local mHeader = readMotionHeader f
						if mHeader.magic != 544501613 then ( --mot
							messagebox "Not supported"; fclose f; return 0
						)
						
						--locate bone headers:
						fseek f pointers[1] #seek_set
						local firstHeader = readMotionHeader f
						fseek f (mHeader.offsToBoneHdrOffs+start) #seek_set
						local useOuterBoneHeaders = false 
						local boneHdrOffs = readlonglong f
						local boneHdrCount = readlonglong f
						if boneHdrCount == undefined or boneHdrCount > 1000 and start != pointers[1] then (
							start = pointers[1]
							fseek f (firstHeader.offsToBoneHdrOffs+start) #seek_set
							local boneHdrOffs = readlonglong f
							local boneHdrCount = readlonglong f
							print "Using bone headers from mot 1"
							useOuterBoneHeaders = true
						) 
						
						--collect bone headers:
						if boneHdrCount < 1000 and boneHdrOffs < fileSize then (
							fseek f (boneHdrOffs + start) #seek_set
							local motBoneHeaders = #()
							for j=1 to boneHdrCount do append motBoneHeaders (readMotBoneHeader f start)
						)
						
						start = pointers[currentItemIdx]
						objSelected = selection as array
						for p in objSelected where superclassof p == GeometryClass and p.children != undefined do join objSelected p.children
						
						--apply positions to selected bones:
						undo on (
							at time -999999 (										
								for i = 1 to objSelected.count do (
									local clean_name = filterstring objSelected[i].name ":"; clean_name = clean_name[clean_name.count]
									for b = 1 to motBoneHeaders.count do (
										if clean_name == motBoneHeaders[b].boneName then ( --objSelected[i].parent != undefined and
											if Chk_ImportPositions.checked then
												objSelected[i].pos.controller.value = (motBoneHeaders[b].translation * boneScale)
											if motBoneHeaders[b].parentOffs > 0 then
												if Chk_TPose.checked then
													objSelected[i].rotation.controller.value *= (inverse objSelected[i].rotation.controller.value)
												else if Chk_ImportRotations.checked then
													objSelected[i].rotation.controller.value = inverse motBoneHeaders[b].quaternion
											exit
										)
									)
								)
							)
						)
						fclose f
						messagebox "Bone positions imported!"
						destroydialog SelectAnim
					)
					
					on ExportButton pressed do (
						local revSkip = 0; if version == 486 then revSkip = 8
						--clearlistener()
						actionMan.executeAction 0 "40472" --open listener
						setListenerSel #(-1,-1) --write to the end of listener
						framerate = 60
						local animScale = 1.0
						if doScale == true then animScale = 0.01
						format "\nMotlist Export: % \n" animItems[currentItemIdx] 
						format "Animation range: % to %\n" animationRange.start animationRange.end
						if doStartTime == true and (classof startTime == float) and startTime > -1 then 
							format "Animation will be exported starting from frame: % \n" startTime 
						else doStartTime = false
						if doStopTime == true and (classof stopTime == float) and stopTime > -1 then 
							format "Animation will be exported ending at frame: % \n" stopTime 
						else doStopTime = false
						if doForceScale == true then format "Forcing scale % \n" forcedScale
						
						local f = fopen fileName "rb"
						local fileSize = getFileSize fileName
						local pointers = #()
						
						local fHeader = readHeader f
						version = fHeader.Version
						
						local realVersion = undefined
						if version >= 484 then (
							realVersion = version
							version = 486
						)
						
						local motionIDSize = ( if version >= 486 then 72 else ( if version == 60 then 12 else 24 ) )
						local endClipStart = fHeader.colOffs + motionIDSize * fHeader.numOffs
						local hasEndClipData = (endClipStart + 200 < fileSize and ((findNextOfLong f endClipStart 1346980931) - endClipStart < 200))
						
						
						fseek f fHeader.pointersOffs #seek_set
						for j = 1 to fHeader.numOffs do ( append pointers (readlonglong f) )
						local start = pointers[currentItemIdx]
						
						fseek f start #seek_set
						local mHeader = readMotionHeader f
						--print mHeader
						if mHeader.magic != 544501613 then ( --mot
							messagebox "Not supported"; fclose f; return 0
						)
						
						local motName = animItems[currentItemIdx]
						if mHeader.namesOffs > 0 then (
							fseek f (mHeader.namesOffs+start) #seek_set
							motName = ReadFixedString f 128
						)
						
						--locate & collect bone headers:
						fseek f pointers[1] #seek_set
						local firstHeader = readMotionHeader f
						fseek f (mHeader.offsToBoneHdrOffs+start) #seek_set
						local useOuterBoneHeaders = false 
						local boneHdrOffs = readlonglong f
						local boneHdrCount = readlonglong f
						if boneHdrCount == undefined or boneHdrCount > 1000 and start != pointers[1] then (
							start = pointers[1]
							fseek f (firstHeader.offsToBoneHdrOffs+start) #seek_set
							local boneHdrOffs = readlonglong f
							local boneHdrCount = readlonglong f
							print "Using bone headers from mot 1"
							useOuterBoneHeaders = true
						) 
						print boneHdrCount
						if boneHdrCount < 1000 and boneHdrOffs < fileSize then (
							fseek f (boneHdrOffs + start) #seek_set
							local motBoneHeaders = #()
							for j=1 to boneHdrCount do append motBoneHeaders (readMotBoneHeader f start)
						)
						start = pointers[currentItemIdx]
						
						local writeStart = start
						local offsetAmt = ( if version == 99 or version == 486 then mHeader.boneClipHdrOffs else mHeader.boneClipHdrOffs )
						
						if hasEndClipData and pointers[currentItemIdx] < endClipStart then (
							offsetAmt = 0
							writeStart = fileSize 
							format "\n"; print ("WARNING: Immovable end-CLIP Data detected at position " + (endClipStart as string) +  "!")
							print "The Motlist Tool Will write the new MOT at the end of the file, after this data."; format "\n"
						)
						
						--remove unwanted bones from selection and collect bone hashes:
						local objSelected = #()
						local origSelection = selection as array
						for i = 1 to origSelection.count do (
							if superclassof origSelection[i] != Helper and classof origSelection[i] != BoneGeometry then (
								format "Object % is not a bone object and was skipped. Class = % \n" origSelection[i].name (classof origSelection[i])
							) else (
								local boneHash = generate_hash origSelection[i].name 1 --create valid bone hash from bone name
								setUserprop origSelection[i] "BoneHash" boneHash --save user property
								setUserprop origSelection[i] "BoneHash" boneHash --twice
								if not (numkeys origSelection[i].position.controller == 0 and numkeys origSelection[i].rotation.controller == 0 and numkeys origSelection[i].scale.controller == 0) then 
									append objSelected origSelection[i]
							)
						)
						 
						--clone file:
						if origSelection.count > 0 then (
							local nf = fopen newfileName "wb"
							fseek nf 0 #seek_set; fseek f 0 #seek_set 
							--local tell = ftell f
							
							--format "Reading to % \n" (offsetAmt + writeStart)
							
							for short = 1 to (offsetAmt + writeStart) / 2 do
								writeshort nf (readshort f)
							
							if offsetAmt == 0 then (
								fseek f start #seek_set
								for i = 1 to 116 do 
									writebyte nf (readbyte f) --copy header
								local newMotNameStart = (ftell nf) - writeStart
								writeUnicodeString nf motName
								padToNextLine nf
								fseek nf (writeStart + 80) #seek_set
								writelonglong nf newMotNameStart
								fseek nf 0 #seek_end
							)
							
							padToNextLine nf
						) else (
							fclose f
							messageBox "Select one or more bones!"; destroydialog SelectAnim
							return false
						)
						format "Exporting % Bones to % \n" objSelected.count newFileName
						
						--collect old bone clip headers
						local oldBoneClipHdrs = #()
						fseek f (mHeader.boneClipHdrOffs+start) #seek_set
						if version == 99 or version == 60 or version == 486 then  
							for i = 1 to mHeader.boneClipCount do (append oldBoneClipHdrs (readBoneClipHdrRE3 f))
						else if version == 85 then
							for i = 1 to mHeader.boneClipCount do (append oldBoneClipHdrs (readBoneClipHdrRE2 f))
						
						--collect old track headers
						local oldTrackHeaders = #()
						if oldBoneClipHdrs[1] != undefined then (
							fseek f (oldBoneClipHdrs[1].trackHdrOffs+start) #seek_set
							for i = 1 to mHeader.boneClipCount do ( 
								local trackHeaders = #()
								if ( i == mHeader.boneClipCount or ftell f < oldBoneClipHdrs[i+1].trackHdrOffs+start) then (
									if version == 99 or version == 486 then (
										if bit.and oldBoneClipHdrs[i].trackFlags1 1 > 0 then append trackHeaders (readTrackHdrRE3 f 1) 
										if bit.and oldBoneClipHdrs[i].trackFlags1 2 > 0 then append trackHeaders (readTrackHdrRE3 f 2) 
										if bit.and oldBoneClipHdrs[i].trackFlags1 4 > 0 then append trackHeaders (readTrackHdrRE3 f 3) 
									) else if version == 85 or version == 60 then (
										if bit.and oldBoneClipHdrs[i].trackFlags1 1 > 0 then append trackHeaders (readTrackHdrRE2 f 1) 
										if bit.and oldBoneClipHdrs[i].trackFlags1 2 > 0 then append trackHeaders (readTrackHdrRE2 f 2) 
										if bit.and oldBoneClipHdrs[i].trackFlags1 4 > 0 then append trackHeaders (readTrackHdrRE2 f 3) 
									)
								)
								append oldTrackHeaders trackHeaders
							) 
						)
						
						if version == 85 or version == 60 then 
							local flag2 = 0
						else local flag2 = -1
						
						local boneClipHdrs = #()
						local sortedObjs = #()
						local startOffs = 0
						 
						--organize bone clip headers bones to be breadth-first:
						parents = makeUniqueArray (for o in objSelected collect (getRoot o)) 
						local sortedSelection = #(parents[1])
						for p in parents do 
							for c in (breadthFirstSearch p) do (
								local dontAdd = true
								for k = 1 to objSelected.count do if c == objSelected[k] then ( dontAdd = false; exit )
								local numPosKeys = numkeys c.position.controller
								local numRotKeys = numkeys c.rotation.controller
								local numSclKeys = numkeys c.scale.controller
								if dontAdd == false and not (numPosKeys == 0 and numRotKeys == 0 and numSclKeys == 0) then 
									if isUselessController c.position.controller and isUselessController c.rotation.controller and isUselessController c.scale.controller then
										format "Omitting non-animated bone %\n" c.name
									else
										appendIfUnique sortedSelection c
							)
						makeUniqueArray sortedSelection
						
						--prepare bone clip headers
						for i = 1 to sortedSelection.count do (
							local idx = i
							for k = 1 to objSelected.count do if sortedSelection[i] == objSelected[k] then (idx = k; exit)
							append boneClipHdrs (BoneClipHdrRE2 startOffs (idx-1) 7 flag2 (getuserprop sortedSelection[i] "BoneHash") 1 0 0)
							append sortedObjs sortedSelection[i]
							startOffs += 12
						)
						
						--write RE2 or RE7 bone headers:
						if version == 85 or version == 60 then 
							local newBoneHeaders = packAndwriteMotBoneHeaders f nf objSelected motBoneHeaders mHeader writeStart animScale startTime
						
						local newBoneClipHdrOffs = (ftell nf)

						--write bone clip headers:
						for i = 1 to boneClipHdrs.count do ( 
							boneClipHdrs[i].address = (ftell nf)
							writeBoneClipHeader nf boneClipHdrs[i]
						)
						padToNextLine nf
						local trackHeadersOffs = (ftell nf)
						
						local maxFrame = 0.0
						local firstFrame = 0.0
						local trackHdrCount = 0
						local allFrameData = #()
						
						--Prepare frame data:
						with animate on 
						(						
							--Find min and max timeframes:						
							firstFrame = animationRange.start
							maxFrame = animationRange.end -- - 1
							
							if doStartTime == true then (
								if doStopTime == true then if startTime > stopTime then startTime = stopTime
								if startTime > firstFrame then firstFrame = startTime
							) if doStopTime == true then (
								if doStartTime == true then if stopTime < startTime then stopTime = startTime
								if stopTime < maxFrame then maxFrame = stopTime
							)
							
							--Make sure each controller has a keyframe at first and last frame:
							for i = 1 to sortedObjs.count do (
								local posController = sortedObjs[i].pos.controller; if hasproperty posController "x_Position" then posController = posController.x_Position.controller
								local rotController = sortedObjs[i].rotation.controller; if hasproperty rotController "x_Rotation" then rotController = rotController.x_Rotation.controller
								local scaleController = sortedObjs[i].scale.controller; if hasproperty scaleController "x_Scale" then scaleController = scaleController.x_Scale.controller
								if (numkeys sortedObjs[i].pos.controller) > 0 		and not isUselessController sortedObjs[i].pos.controller then ( addNewKey posController firstFrame; addNewKey posController maxFrame )
								if (numkeys sortedObjs[i].rotation.controller) > 0 	and not isUselessController sortedObjs[i].rotation.controller then ( addNewKey rotController firstFrame; addNewKey rotController maxFrame )
								if (numkeys sortedObjs[i].scale.controller) > 0		and not isUselessController sortedObjs[i].scale.controller then ( addNewKey scaleController firstFrame; addNewKey scaleController maxFrame )
							)
							
							local keysDropped = 0; local totalKeys = 0; local usedKeys = 0; local startOffs = 0
							for i = 1 to sortedObjs.count do (
								local numControllers = 3
								
								--Prepare keyframe data:
								local frameData = #(); local flags = 0; local type = -1
								for j = 1 to numControllers do (
									if type < 1 and (numkeys sortedObjs[i].pos.controller) > 0 and not isUselessController sortedObjs[i].pos.controller then (
										type = 1; flags += 1
										local keyRanges = GetStartEndKeys sortedObjs[i] type (interval firstFrame maxFrame)
									) else if type < 2 and (numkeys sortedObjs[i].rotation.controller) > 0 and not isUselessController sortedObjs[i].rotation.controller then (
										type = 2; flags += 2
										local keyRanges = GetStartEndKeys sortedObjs[i] type (interval firstFrame maxFrame)
									) else if type < 3 and (numkeys sortedObjs[i].scale.controller) > 0 and not isUselessController sortedObjs[i].scale.controller then (
										type = 3; flags += 4
										if doForceScale == true then (
											scaleKeyCount = 1
											local keyRanges = #(1, 1, #(sortedObjs[i].scale.controller.keys[1])) --GetKeyIndex sortedObjs[i].scale.controller firstFrame
										) else local keyRanges = GetStartEndKeys sortedObjs[i] type (interval firstFrame maxFrame)
									)
									
									if keyRanges == undefined then (
										--format "FATAL ERROR: bone % could not find expected keyframes on track %\n" sortedObjs[i].name type; 
										continue --return 0 
									)
									local rawTrackKeys = keyRanges[3]
									
									--optimize keyframes:
									if doOptimize == true then (
										local trackKeys = #()
										local position; local rotation; local theScale
										local prevPosition; local prevRotation; local prevScale
										local nextPosition; local nextRotation; local nextScale
										for key = 1 to rawTrackKeys.count do (										
											if key == 1 or (key == rawTrackKeys.count and trackKeys.count != 1) then (
												append trackKeys rawTrackKeys[key].time --add the first and the last frame, unless the last would be the 2nd
											) else if type == 1 then ( 
												if key == rawTrackKeys.count then 
													nextPosition = at time rawTrackKeys[1].time sortedObjs[i].pos.controller.value
												else 
													nextPosition = at time rawTrackKeys[key+1].time sortedObjs[i].pos.controller.value
												if key == 2 then (
													position =  at time rawTrackKeys[key].time sortedObjs[i].pos.controller.value
													prevPosition = at time rawTrackKeys[1].time sortedObjs[i].pos.controller.value
												) else (
													prevPosition = position
													position = nextPosition
												) 
												if position != prevPosition or position != nextPosition then 
													appendIfUnique trackKeys rawTrackKeys[key].time
											) else if type == 2 then ( 
												if key == rawTrackKeys.count then 
													nextRotation = at time rawTrackKeys[1].time sortedObjs[i].rotation.controller.value
												else 
													nextRotation = at time rawTrackKeys[key+1].time sortedObjs[i].rotation.controller.value
												if key == 2 then (
													rotation =  at time rawTrackKeys[key].time sortedObjs[i].rotation.controller.value
													prevRotation = at time rawTrackKeys[1].time sortedObjs[i].rotation.controller.value
												) else (
													prevRotation = rotation
													rotation = nextRotation
												)
												if rotation != prevRotation or rotation != nextRotation then ( --fix Revilmax flipping-bones errors
													if  (bit.isNan rotation.x or bit.isNan rotation.y or bit.isNan rotation.z ) then (
													--or ((rotation.x > 0 and prevRotation.x < 0) or (rotation.x < 0 and prevRotation.x > 0 )) \
													--and ((rotation.y > 0 and prevRotation.y < 0) or (rotation.y < 0 and prevRotation.y > 0 )) \
													--and ((rotation.z > 0 and prevRotation.z < 0) or (rotation.z < 0 and prevRotation.z > 0 )) then (
														format "Dropped broken rotation keyframe at % for bone % \n" rawTrackKeys[key].time sortedObjs[i].name
													) else
														appendIfUnique trackKeys rawTrackKeys[key].time
												)
											) else if type == 3 then ( 
												if key == rawTrackKeys.count then 
													nextScale = at time rawTrackKeys[1].time sortedObjs[i].scale.controller.value
												else 
													nextScale = at time rawTrackKeys[key+1].time sortedObjs[i].scale.controller.value
												if key == 2 then (
													theScale =  at time rawTrackKeys[key].time sortedObjs[i].scale.controller.value
													prevScale = at time rawTrackKeys[1].time sortedObjs[i].scale.controller.value
												) else (
													prevScale = theScale
													theScale = nextScale
												) 
												if theScale != prevScale or theScale != nextScale then 
													appendIfUnique trackKeys rawTrackKeys[key].time
											)
										)
									) else 
										local trackKeys = for key in rawTrackKeys collect key.time
									
									keysDropped += (rawTrackKeys.count - trackKeys.count); totalKeys += rawTrackKeys.count; usedKeys += trackKeys.count
									
									if rawTrackKeys.count == 1 and rawTrackKeys[1] != 0 
										then rawTrackKeys[1] = 0
									
									--prepare transform data
									local transformData = #()
									for kf = 1 to trackKeys.count do (
										at time (trackKeys[kf]) (
											if type == 1 then (
												local localPosition =  sortedObjs[i].pos.controller.value * animScale
												if hasValidParent sortedObjs[i] then ( --normal bones (position):
													append transformData localPosition
												) else ( --root bone (position):
													append transformData [localPosition.x , localPosition.z, -localPosition.y] 
												) 
											)
											else if type == 2 then  ( 		--normal bones:
												if hasValidParent sortedObjs[i] then (
													local localRotation =  sortedObjs[i].rotation.controller.value
													if localRotation.w < 0 then (
														append transformData (localRotation)
													) else append transformData (inverse localRotation)
												) else ( 			  		--root bone (rotation):
													local rootRotation = (inverse (sortedObjs[i].transform.controller.value * (matrix3 [1,0,0][0,0,-1][0,1,0][0,0,0])).rotation)
													if rootRotation.w < 0 then rootRotation = inverse rootRotation; 
													rootRotation.w = abs rootRotation.w
													append transformData (normalize  rootRotation)
												)
											) else if type == 3 then  ( 	--(scale)
												if doForceScale == true then (
													append transformData [forcedScale, forcedScale, forcedScale]
												) else append transformData sortedObjs[i].scale.controller.value
											)
										)
									)
									
									append frameData #(type, trackKeys, transformData, startOffs)
									startOffs += (transformData.count * 4) + (trackKeys.count * 2)
									trackHdrCount += 1
								)
								append allFrameData frameData
								boneClipHdrs[i].trackFlags1 = flags
							)
							maxFrame = ((formattedprint (maxFrame - firstFrame)) as float)
							if doOptimize == true then 
								format "Frame Count: % \nRemoved % redundant keyframes out of % total (%\%), finishing with % keyframes \n" maxFrame keysDropped totalKeys (keysDropped / totalKeys as float * 100) usedKeys
							else 
								format "Frame Count: % \nExporting % keyframes \n" maxFrame usedKeys
							
							local trackHdrSize = trackHdrCount * 20
							if version == 85 then trackHdrSize = trackHdrCount * 40
							local frameDataStart = trackHeadersOffs + trackHdrSize
							local allTtrackHeaders = #()
							
							--write track headers
							for i = 1 to sortedObjs.count do (
								local trackHeaders = #()
								for j = 1 to allFrameData[i].count do (
									local flags = 4194546 --uncompressed translation & scale, RE2 or RE3 
									if allFrameData[i][j][1] == 2 then (
										if version == 99 or version == 486 then flags = 4981010 --uncompressed rotations RE3
										else if version == 85 or version == 60 then flags = 4915474 --uncompressed rotations RE2 / RE7
									)
									
									if allFrameData[i][j][2].count == 0 then ( --make emergency placeholder
										format "WARNING: Expected keyframe data[%] for Bone %\n" j sortedObjs[i].name
										append allFrameData[i][j][2] 0
										append allFrameData[i][j][3] [0, 0, 0]
									)
									append trackHeaders (trackHdrRE2 (ftell nf) flags (allFrameData[i][j][2].count) mHeader.frameRate (maxFrame) (frameDataStart+allFrameData[i][j][4]-writeStart) (frameDataStart+allFrameData[i][j][4] + 2*allFrameData[i][j][2].count-writeStart) 0 (frameDataStart+allFrameData[i][j][4]))
									writeTrackHeader nf trackHeaders[trackHeaders.count]
								)
								append allTtrackHeaders trackHeaders
							)
							ctr = 0
							--write frame data
							for i = 1 to sortedObjs.count do (
								for j = 1 to allFrameData[i].count do (
									allTtrackHeaders[i][j].frameIndOffs = (ftell nf) - writeStart
									for fr = 1 to allFrameData[i][j][2].count do (
										writeshort nf (allFrameData[i][j][2][fr] - firstFrame + 0.5) #signed
									)
									allTtrackHeaders[i][j].FrameDataOffs = (ftell nf) - writeStart
									for fr = 1 to allFrameData[i][j][3].count do (
										writefloat nf allFrameData[i][j][3][fr].x --keyframe translations, rotations and scales
										writefloat nf allFrameData[i][j][3][fr].y
										writefloat nf allFrameData[i][j][3][fr].z
									)
								)
							)
							padToNextLine nf --padding
						)
						local frameDataEnd = ftell nf
						
						--fix bone clip headers:
						for i = 1 to boneClipHdrs.count do (
							--print boneClipHdrs[i]
							fseek nf (boneClipHdrs[i].address+2) #seek_set
							writebyte nf boneClipHdrs[i].trackFlags1
							writebyte nf boneClipHdrs[i].trackFlags2
							if version == 85 then (fseek nf 12 #seek_cur) else (fseek nf 4 #seek_cur)
							writelong nf (allTtrackHeaders[i][1].address - writeStart) #unsigned
						)
						
						--fix track headers:
						for i = 1 to sortedObjs.count do (
							for j = 1 to allFrameData[i].count do (
								if version == 99 or version == 486 then (
									fseek nf (allTtrackHeaders[i][j].address + 8 ) #seek_set
									if allTtrackHeaders[i][j].keyCount == 1 and version == 99 then 
										writelong nf 0 #unsigned
									else writelong nf (allTtrackHeaders[i][j].frameIndOffs ) #unsigned
									writelong nf (allTtrackHeaders[i][j].frameDataOffs ) #unsigned
								) else if version == 85 or version == 60 then (
									fseek nf (allTtrackHeaders[i][j].address + 16 ) #seek_set
									writelonglong nf (allTtrackHeaders[i][j].frameIndOffs ) #unsigned
									writelonglong nf (allTtrackHeaders[i][j].frameDataOffs ) #unsigned
								)
							)
						)
						local nextMotPos = (findNextOfLong f (ftell f) 544501613) - 4 --'mot '
						if fHeader.colOffs < nextMotPos and fHeader.colOffs > ftell f then 
							nextMotPos = fHeader.colOffs
						local lastUnpackOffs = 0
						if oldTrackHeaders.count > 0 and oldTrackHeaders[oldTrackHeaders.count].count > 0 then lastUnpackOffs = oldTrackHeaders[oldTrackHeaders.count][oldTrackHeaders[oldTrackHeaders.count].count].unpackDataOffs
						
						local origFrameDataEnd = nextMotPos
						
						--find end of original frame data (without reading it):
						if mHeader.Offs1 > 0 then --if not RE8:
							origFrameDataEnd = mHeader.Offs1+start --find start of jmap string
						else if mHeader.clipFileOffset > 0 then 
							origFrameDataEnd = mHeader.clipFileOffset+start --if no string, find start of CLIP file
						else if mHeader.Offs2 > 0 then 
							origFrameDataEnd = mHeader.Offs2+start --If no CLIP file, find start of dataPointers
						else if version == 99 or (version == 486 and mHeader.namesOffs > 0) then 
							origFrameDataEnd = mHeader.namesOffs+start
						else if version == 99 or version == 486 and mHeader.offsToBoneHdrOffs < mHeader.motSize then 
							origFrameDataEnd = mHeader.offsToBoneHdrOffs+start --If RE3 & no dataPointers, find start of bone headers
						else if start < fHeader.colOffs and nextMotPos > fHeader.colOffs then 
							origFrameDataEnd = fHeader.colOffs
							
						if lastUnpackOffs > 0 and lastUnpackOffs < fileSize then 
							if (lastUnpackOffs+32+start) < origFrameDataEnd then 
								origFrameDataEnd = (lastUnpackOffs+32+start) --if an unpackDataOffs exists for the final track framedata and it + its size (32) is for some reason lower than the above offset, then use that instead
						
						fseek f (origFrameDataEnd) #seek_set
						fseek nf frameDataEnd #seek_set
						
						local diff = ((ftell nf) - (writeStart - start)) - (ftell f)
						--format "Diff: % origFrameDataEnd: % \n" diff origFrameDataEnd
						
						if version == 486 and mHeader.offs1 > 0 and mod (mHeader.offs1 + diff + start) 16 != 0 then --JMAP padding for RE8
							while mod (mHeader.offs1 + diff + start) 16 != 0 do (
								diff += 1
								writebyte nf 0
							)
						--format "Diff: % ftell f: % \n" diff (ftell f)
						
						--copy bytes up to end of file:
						if version == 85 or version == 60 then (
							
							local remainingBytes = fileSize - origFrameDataEnd
							if offsetAmt == 0 then 
								remainingBytes = nextMotPos - origFrameDataEnd
							
							--format "starting at f % nf % , remainingBytes: % \n" (ftell f) (ftell nf) remainingBytes
							for short = 1 to (remainingBytes / 2) do
								writeshort nf (readshort f)
							--format "ending at f % nf % \n" (ftell f) (ftell nf)
							
						) else if version == 99 or version == 486 then (
							--if offsetAmt > 0 then (
								if writeStart < fHeader.colOffs and nextMotPos > fHeader.colOffs then 
									local remainingBytes = fHeader.colOffs - origFrameDataEnd  
								else local remainingBytes = nextMotPos - origFrameDataEnd
								for short = 1 to (remainingBytes / 2) do writeshort nf (readshort f) --copy to start of old bone headers
								padToNextLine nf
							--)
							--Bone headers RE3:
							local newBoneHeaders = packAndwriteMotBoneHeaders f nf objSelected motBoneHeaders mHeader writeStart animScale firstFrame
							local motSize = (ftell nf) - writeStart
							
							--copy rest of file after bone headers:
							if offsetAmt > 0 then (
								fseek f nextMotPos #seek_set
								for short = 1 to (fileSize - nextMotPos) / 2 do writeshort nf (readshort f)
							)
						)
						
						
						if version == 85 or version == 60 then
							local motSize = ((findNextOfLong f (origFrameDataEnd) 544501613) - 4) - start 
						
						--fix other offsets:
						fseek nf (writeStart+12) #seek_set
						if version == 486 or version == 99 then
							writelong nf 0 
						else 
							writelong nf motSize
						
						fseek nf (writeStart+24) #seek_set
						writelonglong nf (newBoneClipHdrOffs-writeStart) #unsigned --boneClipHdrOffs
						
						if mHeader.clipFileOffset > 0 then (
							fseek nf (writeStart+48) #seek_set --clipFileOffset
							--format "ClipFileOffset at: %\n" (ftell nf)
							writelong nf (mHeader.clipFileOffset+diff)
						)
						
						if mHeader.Offs1 > 0 then (
							fseek nf (writeStart+56) #seek_set --Offs1
							--format "Offs1 at: %\n" (ftell nf)
							writelong nf (mHeader.Offs1+diff)
						)
						
						if mHeader.Offs2 > 0 then (
							fseek nf (writeStart+72+revSkip) #seek_set --Offs2
							--format "Offs2 at: %\n" (ftell nf)
							writelong nf (mHeader.Offs2+diff)
						)
						
						fseek nf (writeStart+104+revSkip) #seek_set 
						--format "boneCount at: %\n" (ftell nf)
						writeshort nf objSelected.count --boneCount 
						writeshort nf sortedObjs.count --boneClipCount
						
						fseek nf (writeStart+88+revSkip) #seek_set
						writefloat nf ( maxFrame ) --frameCount
						fseek nf 4 #seek_cur --blending (skip)
						fseek nf 4 #seek_cur --uknFloat1
						writefloat nf ( maxFrame ) --uknFloat2
						
						--fix CLIP blocks and offs2 stuff:
						if mHeader.clipFileOffset > 0 then (
							fseek f (mHeader.clipFileOffset+start) #seek_set
							fseek nf (mHeader.clipFileOffset+diff+writeStart) #seek_set
							format "Fixing CLIP at F %, NF %\n" (ftell f) (ftell nf)
							if version == 486 and mHeader.namesOffs > 0 then 
								local endOfClip = mHeader.namesOffs + start
							else if version == 85 and mHeader.Offs2 > 0 then 
								local endOfClip = mHeader.Offs2 + start
							else 
								local endOfClip = (findNextOfLong f (mHeader.clipFileOffset+start) 544501613 ) - 4 --'mot '
								
							--if start < fHeader.colOffs and endOfClip > fHeader.colOffs then 
							--	endOfClip = fHeader.colOffs
								
							local lastCLIP = ftell f 
							local numCtracks = 0
								
							while (ftell f) < endOfClip do ( 
								local testExtraSure = readShort f #unsigned
								fseek f -2 #seek_cur
								local tester = readlonglong f #unsigned
								if tester > mHeader.boneClipHdrOffs and tester > mHeader.clipFileOffset and tester < endOfClip - start then ( --ftell f < lastCLIP+112 or ftell f > lastCLIP + numCtracks*40) and 
									if testExtraSure != 0 then (
										--format "Writing % at CLIP f % / nf % , because % is greater than % and smaller than %\n"  (tester+diff) (ftell f - 8) (ftell nf) tester mHeader.clipFileOffset (endOfClip - start)
										writelonglong nf (tester+diff) #unsigned
									) else (
										--format "There was a collision detecting a CLIP offset at f % / nf %\n" (ftell f - 8) (ftell nf)
										fseek nf 8 #seek_cur
									)
								) else fseek nf 8 #seek_cur
							)
							format "Stopped fixing CLIP at F %, NF %\n" (ftell f) (ftell nf)
						)
						
						if version == 486 and mHeader.namesOffs > 0 then ( --correct nameOffs for RE8
							fseek nf (writeStart+88) #seek_set
							--format "Writing % at %" (mHeader.namesOffs + diff) (ftell nf) 
							writelonglong nf (mHeader.namesOffs + diff)
						) else (
							--format "Not adjusting names offset %, version % " (mHeader.namesOffs) (version) 
							--print mHeader
						)
						
						fseek nf 0 #seek_end; 
						local newFileSize = ftell nf
						diff = newFileSize - fileSize --Use full difference for Pointers and colOffs
						
						if fHeader.colOffs > writeStart then (
							fseek nf 24 #seek_set; --colOffs
							writelong nf (fHeader.colOffs+diff)
						)
						
						--fix motlist pointers:
						fseek nf fHeader.pointersOffs #seek_set
						for j = 1 to fHeader.numOffs do (
							if pointers[j]==start then 
								writelonglong nf writeStart
							else if pointers[j] > writeStart then 
								writelonglong nf (pointers[j]+diff)
							else 
								fseek nf 8 #seek_cur
						)
						
						--fix post-motlist CLIP data (rare, and this fixes nothing)
						local motIndSize = (fHeader.numOffs * 24); 
						if version == 60 then 
							motIndSize = (fHeader.numOffs * 16)
						else if realVersion != undefined and realVersion > 486 then 
							motIndSize = (fHeader.numOffs * 72)
							
						local newClipStart = (fHeader.colOffs + motIndSize)
						if newClipStart < fileSize and start < newClipStart and (findNextOfLong f newClipStart 1346980931) - newClipStart < 200 then ( --if there is 'CLIP' magic within 200 bytes of the end of mot indices 
							format "\n"
							--print "WARNING: Immovable CLIP data was detected at the end of this motlist!"
							--print "You must mot-swap your mot to be positioned AFTER this data"
							--print ("If motion data was inserted before position " + (newClipStart as string) + ", the game will crash")
							/*fseek f newClipStart #seek_set ; fseek nf (newClipStart+ diff) #seek_set --go to end of mot indices
							local endOfClip = (findNextOfLong f (ftell f) 544501613) - 4 --next 'mot ' or end-of-file
							format "End CLIP detected at f %, nf % , fileSize = %\n" (ftell f) (ftell nf) fileSize
							while (ftell f) < endOfClip do ( 
								local tester = readlonglong f #unsigned
								if tester > newClipStart and tester < endOfClip then (
									--format "Writing % at f % / nf % , because % is greater than % and smaller than %\n"  (tester+diff) (ftell f) (ftell nf) tester newClipStart endOfClip
									writelonglong nf (tester+diff) #unsigned
								) else fseek nf 8 #seek_cur
							)
							format "CLIP end at f %, nf % \n" (ftell f) (ftell nf)*/
						)
						
						--crash fix:
						fseek nf (writeStart + revSkip + 109) #seek_set --uknPointer3Count
						writebyte nf 0
						
						if doDisableClip == true then (
							fseek nf (writeStart+48) #seek_set; writelonglong nf 0
							writelonglong nf 0; writelonglong nf 0; writelonglong nf 0
							fseek nf (start+108+revSkip) #seek_set; writeshort nf 0
						)
						
						fclose f; fclose nf
						messagebox ("Complete!")
						destroydialog SelectAnim
					)
				)
				destroydialog SelectAnim
				createdialog SelectAnim 300 210
				SelectAnim.animItems = animItems; SelectAnim.doScale = doScale; SelectAnim.doOptimize = doOptimize; SelectAnim.doForceScale = doForceScale; SelectAnim.forcedScale = forcedScale
				SelectAnim.doStartTime=doStartTime; SelectAnim.startTime=startTime; SelectAnim.doStopTime=doStopTime; SelectAnim.stopTime=stopTime; SelectAnim.doDisableClip = doDisableClip
			) else messagebox ("Bad file magic / unsupported motlist version! Select a valid motlist file")
			fclose f
		)
	)

	try ( destroydialog SelectAnim ) catch ( global SelectAnim )
	try ( destroydialog motlistMod ) catch ( global motlistMod )
	rollout motlistMod "MOTLIST TOOL v0.85" 
	(
		local forcedScale = 1.0
		local startTime = formattedprint animationRange.start as float
		local stopTime = formattedprint animationRange.end as float
		local BoneRenameValue = "RE2 <--> DMC5"
		group "Export" (
			checkbox chk_Scale100 "Edit at 100x Scale" checked:true
				toolTip:"Use this if your animation is not ant-sized"
			checkbox chk_doOptimize "Optimize Keyframes" checked:true 
				toolTip:"Removes redundant keyframes from export that are the same as both of their neighbors"
			checkbox chk_doDisableCLIP "Disable CLIP Data"
				toolTip:"Nulls out extra data about the action of the animation, such as particle or hitbox or special data.\nUse this for troubleshooting"
			checkbox chk_doForceScale "Force Scale: " checked:true
				toolTip:"Forces each bone to have only one keyframe of scale, and sets that scale to the value in the field"
			edittext fldForceScale "" text:"1.0" fieldWidth:45 labelOnTop:false offset:[85, -20]
			checkbox chk_doStartTime "Start Frame: " --checked:true
				toolTip:"Export animation frames starting from this time"
			edittext fldStartTime "" text:((formattedprint startTime as float) as string) fieldWidth:45 labelOnTop:false offset:[85, -20]
			checkbox chk_doStopTime "End Frame: " --checked:true
				toolTip:"Export animation frames up until this time"
			edittext fldStopTime "" text:((formattedprint stopTime as float) as string) fieldWidth:45 labelOnTop:false offset:[85, -20]
			button OpenMotlistButton "OPEN .MOTLIST"
				toolTip:"Open a motlist file to pick an animation from it"
		)
		
		group "Utilities" (
			button PurgeBadKeyframes "Purge Bad Keyframes"
				toolTip:"Deletes keyframes from selected bones containing rotations with invalid values"
			button DoResetScale "Reset Bone Scale/Transforms"
				toolTip:"Resets the scale of the selected bones. Right click to reset transforms"
			button MoveAnimToCenter "Center Animation"
				toolTip:"Moves the root bone of the selected animated bones to [0,0,0]"
			button CenterOverRoot "Center Over Root"
				toolTip:"Moves the selected animated bones horizontally to be centered above/below their root bone"
			button ReParentButton "Re-Parent"
				toolTip:"Select two bones, A and B, and bone B will be changed to become a child of bone A without its animation being moved"
			--button CloneBoneButton "Clone bone"
				--toolTip:"With two bones selected, makes a copy of bone 1 and puts it in the place of bone 2.\nUse this to fix bones imported with bad keyframes"
			button FixHeightButton "Fix Animation Height"
				toolTip:"Forces the selected root bone to always be on the ground (with root bone selected)"
			button SetUprightButton "Set Animation Upright"
				toolTip:"Rotates a selected root bone to its original transform, then rotates it forward 90 degrees. \nRight-click on the bottom 3 buttons in this menu to flip manually (with root bone selected)"
			dropdownlist BoneRenameMenu "Retarget Bones" items:#("RE2 <--> DMC5", "RE2 <--> RE8", "MMD --> DMC5", "DMC5 <--> SF6")
			button BoneRenameButton "Retarget Bones" align:#left
				toolTip:"Renames selected bones from the RE2 naming scheme to the DMC5 one, or vice versa"
			checkbox Chk_Reparent "Reparent" offset:[95, -22]
				toolTip:"For RE2 <--> RE8, this will change the parenting of certain bones to match the expected hierarchy of each game"
		)
		hyperlink lbl6 "By alphaZomega" address: "https://residentevilmodding.boards.net/thread/14132/motlist-maxscript-custom-animations-engine" align:#right
		
		timer range_timer interval:100
		fn check_ranges = (
			if startTime < animationRange.start or stopTime > animationRange.end then (
				startTime = animationRange.start
				stopTime = animationRange.end
				fldStartTime.text = ((formattedprint startTime as float) as string)
				fldStopTime.text = ((formattedprint stopTime as float) as string)
			)
		)
		
		on range_timer tick do check_ranges()
		--on Ro_cameras open do updateCameras()
		--on ddl_cams selected i do select cams[i]
		
		
		on BoneRenameMenu selected i do ( BoneRenameValue = BoneRenameMenu.items[i] )
		on fldForceScale entered num do ( forcedScale = ((formattedprint num)+"f") as float )
		on fldStartTime entered num do (chk_doStartTime.checked = true; startTime = ((formattedprint num)+"f") as float)
		on fldStopTime entered num do (chk_doStopTime.checked = true; stopTime = ((formattedprint num)+"f") as float)
		on OpenMotlistButton pressed do (
			openMotlist (
				GetMultiOpenFilenames \
					caption:"Open motlist: Select *.motlist.* File" \
					types: "motlist files (*.motlist.*)|*.motlist.*"
			) forcedScale startTime stopTime doScale:chk_Scale100.state doOptimize:chk_doOptimize.state doForceScale:chk_doForceScale.state doStartTime:chk_doStartTime.state doStopTime:chk_doStopTime.state  doDisableClip:chk_doDisableCLIP.state
		)
		
		on DoResetScale pressed do (
			with undo on (
				local bones = for obj in selection as array where superclassof obj == Helper or superclassof obj == BoneGeometry collect obj
				for bone in bones do resetscale bone
			)
		)
		
		on DoResetScale rightclick do (
			with undo on (
				local bones = for obj in selection as array where superclassof obj == Helper or superclassof obj == BoneGeometry collect obj
				for bone in bones do resettransform bone
			)
		)
		
		on PurgeBadKeyframes pressed do (
			local objSelected = selection as array
			local totalRemoved = 0
			format "Purging broken rotation keyframes for animation range: % to %\n" animationRange.start animationRange.end
			with undo on (
				for i = 1 to objSelected.count do (
					local keyTimesToDelete = #()
					if (superclassof objSelected[i] == Helper or classof objSelected[i] == BoneGeometry) and numKeys objSelected[1].rotation.controller > 0 then (
						with animate on (
							local controller = objSelected[i].rotation.controller
							local keyRanges = GetStartEndKeys objSelected[i] 2 (interval (animationRange.start) (animationRange.end)) 
							if keyRanges == undefined then continue
							local rawTrackKeys = for key in keyRanges[3] collect ((substring (filterstring (key as string) " ")[3] 5 -1) as integer) --extract frame index from Maxkey name
							for fr = 1 to rawTrackKeys.count do at time (getKeyTime objSelected[i].rotation.controller rawTrackKeys[fr]) (
								/*
								local rotation = at time (getKeyTime objSelected[i].rotation.controller fr) objSelected[i].rotation.controller.value 
								local prevRotation; local nextRotation;
								if fr == rawTrackKeys.count then 
									nextRotation = at time rawTrackKeys[1] objSelected[i].rotation.controller.value
								else 
									nextRotation = at time rawTrackKeys[fr+1] objSelected[i].rotation.controller.value
								if fr == 1 then (
									rotation =  at time rawTrackKeys[fr] objSelected[i].rotation.controller.value
									prevRotation = at time rawTrackKeys[rawTrackKeys.count-1] objSelected[i].rotation.controller.value
								) else (
									prevRotation = rotation
									rotation = nextRotation
								)
								*/
								if (bit.isNan objSelected[i].rotation.controller.value.x or bit.isNan objSelected[i].rotation.controller.value.y or bit.isNan objSelected[i].rotation.controller.value.z) then 
								/*or ((((rotation.x > 0 and prevRotation.x < 0) or (rotation.x < 0 and prevRotation.x > 0 )) \
								and ((rotation.y > 0 and prevRotation.y < 0) or (rotation.y < 0 and prevRotation.y > 0 )) \
								and ((rotation.z > 0 and prevRotation.z < 0) or (rotation.z < 0 and prevRotation.z > 0 ))) \
								or (((rotation.x > 0 and nextRotation.x < 0) or (rotation.x < 0 and nextRotation.x > 0 )) \
								and ((rotation.y > 0 and nextRotation.y < 0) or (rotation.y < 0 and nextRotation.y > 0 )) \
								and ((rotation.z > 0 and nextRotation.z < 0) or (rotation.z < 0 and nextRotation.z > 0 )))) then*/
									append keyTimesToDelete (getKeyTime objSelected[i].rotation.controller fr)
							)
							for t=(keyTimesToDelete.count) to 1 by -1 do (
								local keyIDX = (getKeyIndex objSelected[i].rotation.controller keyTimesToDelete[t])
								format "Deleting broken rotation keyframe % at time % for bone % \n" keyIDX keyTimesToDelete[t] objSelected[i].name
								deleteKey objSelected[i].rotation.controller keyIDX
								totalRemoved += 1
							)
						)
					)
				)
				format "Purged % broken keyframes from % bones\n" totalRemoved objSelected.count
			)
		)
		
		on MoveAnimToCenter pressed do (
			local objSelected = selection as array
			with undo on (
				with animate on (
					for i = 1 to objSelected.count do (
						if ( superclassof objSelected[i] == Helper or classof objSelected[i] == BoneGeometry ) then (
							if objSelected[i].parent == undefined then ( --or objSelected[i].name == "COG" or
								for fr = 1 to (numKeys objSelected[i].pos.controller) do 
									at time (getKeyTime objSelected[i].pos.controller fr) (
										objSelected[i].pos.x = 0
										objSelected[i].pos.y = 0
									)
								exit
							)
						)
					)
				)
			)
		)
		
		on ReParentButton pressed do (
			local objSelected = selection as array
			if objSelected.count == 2 then (
				local RootBone = objSelected[1]
				local COGBone = objSelected[2]
				local COGPosFrames = #()
				with undo on (
					with animate on (
						for fr = 1 to (numKeys COGBone.pos.controller) do 
							at time (getKeyTime COGBone.pos.controller fr) 
								append COGPosFrames COGBone.pos
						COGBone.parent = RootBone
						for fr = 1 to (numKeys COGBone.pos.controller) do 
							at time (getKeyTime COGBone.pos.controller fr) 
								COGBone.pos = COGPosFrames[fr]
					)
				)
			) else messageBox "Select two bones"
		)
		
		on CenterOverRoot pressed do (
			local objSelected = selection as array
			if selection.count > 0 then (
				with undo on (
					local initialDifferenceX = -1234.5
					local initialDifferenceY = -1234.5
					with animate on (
						for i = 1 to objSelected.count do (
							if ( superclassof objSelected[i] == Helper or classof objSelected[i] == BoneGeometry )  and objSelected[i].parent == undefined then (
								for child in objSelected[i].children do (
									firstFrame = getKeyIndex child.pos.controller animationRange.start
									maxFrame = getKeyIndex child.pos.controller animationRange.end
									if initialDifferenceX == -1234.5 then 
										at time ( getKeyTime child.pos.controller firstFrame) (
											initialDifferenceX = objSelected[i].pos.x - child.pos.x
											initialDifferenceY = objSelected[i].pos.y - child.pos.y
											format "% % %\n" child.name initialDifferenceX initialDifferenceY
										)
									for fr = firstFrame to maxFrame do (
										at time (getKeyTime child.pos.controller fr) (
											child.pos.x += initialDifferenceX
											child.pos.y += initialDifferenceY
										)
									)
								)
								exit
							)
						)
					)
				)
			)
		)
		
		on BoneRenameButton pressed do (
			local initialSelection = selection as array
			local objSelected = #()
			for obj in initialSelection do if (superclassof obj == Helper or classof obj == BoneGeometry) then append objSelected obj
			local bones = #()
			with undo on (
				for i = 1 to objSelected.count do (
				
					if BoneRenameValue == "MMD --> DMC5" then ( 
						--Credit to 琉星雨夜(LiuXingYuYe) for making this:
						local newName = case objSelected[i].name of 
						(
							"全ての親": "root"; 								"root": "全ての親";
							"センター": "Hip"; 									"Hip": "センター";
							"上半身": "Waist"; 						    		"Waist": "上半身";
							"上半身2": "Stomach"; 								"Stomach": "上半身2";
							--"spine_2": "Chest";									"Chest": "spine_2";
							"首": "Neck";				    					"Neck": "首";
							--"neck_1": "Neck_Middle";							"Neck_Middle": "neck_1";
							"頭": "Head";										"Head": "頭";
							--"setProp_B_00": "WeaponConst";						"WeaponConst": "setProp_B_00";
							"足D.L": "L_Thigh";									"L_Thigh":"足D.L";
							"ひざD.L": "L_Shin"; 								"L_Shin": "ひざD.L";
							"足首D.L": "L_Foot";								"L_Foot": "足首D.L";
							--"l_leg_ball": "L_Foot_twist";						"L_Foot_twist": "l_leg_ball";
							"足先EX.L": "L_Toe";								"L_Toe": "足先EX.L";
							--"l_leg_femur_twist_1_H": "L_Thigh_twist_SR"; 		"L_Thigh_twist_SR": "l_leg_femur_twist_1_H";
							"足D.R": "R_Thigh";									"R_Thigh":"足D.R";
							"ひざD.R": "R_Shin"; 								"R_Shin": "ひざD.R";
							"足首D.R": "R_Foot";								"R_Foot": "r_leg_ankle";
							--"r_leg_ball": "R_Foot_twist";						"R_Foot_twist": "r_leg_ball";
							"足先EX.R": "R_Toe";							"R_Toe": "足先EX.R";
							--"r_leg_femur_twist_1_H": "R_Thigh_twist_SR";		"R_Thigh_twist_SR": "r_leg_femur_twist_1_H";
							"肩.R": "R_Shoulder";								"R_Shoulder": "肩.R";
							"腕.R": "R_UpperArm";								"R_UpperArm": "腕.R";
							"ひじ.R": "R_Forearm";								"R_Forearm": "ひじ.R";
							"手首.R": "R_Hand";									"R_Hand": "手首.R";
							--"r_arm_humerus_twist_2_H": "R_UpperArm_twist_SR";	"R_UpperArm_twist_SR": "r_arm_humerus_twist_2_H";
							--"r_arm_radius_twist_1_H": "R_Hand_twistX3_SR";		"R_Hand_twistX3_SR": "r_arm_radius_twist_1_H";
							--"r_arm_radius_twist_2_H": "R_Hand_twistX2_SR";		"R_Hand_twistX2_SR": "r_arm_radius_twist_2_H";
							--"r_arm_radius_twist_3_H": "R_Hand_twistX1_SR";		"R_Hand_twistX1_SR": "r_arm_radius_twist_3_H";
							"肩.L": "L_Shoulder";						        "L_Shoulder": "肩.L";
							"腕.L": "L_UpperArm";				        		"L_UpperArm": "腕.L";
							"ひじ.L": "L_Forearm";						        "L_Forearm": "ひじ.L";
							"手首.L": "L_Hand";									"L_Hand": "手首.L";
							--"l_arm_humerus_twist_2_H": "L_UpperArm_twist_SR";	"L_UpperArm_twist_SR": "l_arm_humerus_twist_2_H";
							--"l_arm_radius_twist_1_H": "L_Hand_twistX3_SR";		"L_Hand_twistX3_SR": "l_arm_radius_twist_1_H";
							--"l_arm_radius_twR_Thumb1ist_2_H": "L_Hand_twistX2_SR";		"L_Hand_twistX2_SR": "l_arm_radius_twist_2_H";
							--"l_arm_radius_twist_3_H": "L_Hand_twistX1_SR";		"L_Hand_twistX1_SR": "l_arm_radius_twist_3_H";
							"親指０.R": "R_Thumb1";								"R_Thumb1": "親指０.R";
							"親指１.R": "R_Thumb2";								"R_Thumb2": "親指１.R";
							"親指２.R": "R_Thumb3";								"R_Thumb3": "親指２.R";
							"人指１.R": "R_IndexF1";							"R_IndexF1": "人指１.R";
							"人指２.R": "R_IndexF2";							"R_IndexF2": "人指２.R";
							"人指３.R": "R_IndexF3";							"R_IndexF3": "人指３.R";
							"中指１.R": "R_MiddleF1";							"R_MiddleF1": "中指１.R";
							"中指２.R": "R_MiddleF2";							"R_MiddleF2": "中指２.R";
							"中指３.R": "R_MiddleF3";							"R_MiddleF3": "中指３.R";
							--"r_hand_ring_0": "R_Palm";							"R_Palm": "r_hand_ring_0";
							"薬指１.R": "R_RingF1";								"R_RingF1": "薬指１.R";
							"薬指２.R": "R_RingF2";								"R_RingF2": "薬指２.R";
							"薬指３.R": "R_RingF3";								"R_RingF3": "薬指３.R";
							"小指１.R": "R_PinkyF1";							"R_PinkyF1": "小指１.R";
							"小指２.R": "R_PinkyF2";							"R_PinkyF2": "小指２.R";
							"小指３.R": "R_PinkyF3";							"R_PinkyF3": "小指３.R";
							"ダミー.R": "R_WeaponHand";							"R_WeaponHand": "ダミー.R";
							"親指０.L": "L_Thumb1";								"L_Thumb1": "親指０.L";
							"親指１.L": "L_Thumb2";								"L_Thumb2": "親指１.L";
							"親指２.L": "L_Thumb3";								"L_Thumb3": "親指２.L";
							"人指１.L": "L_IndexF1";							"L_IndexF1": "人指１.L";
							"人指２.L": "L_IndexF2";							"L_IndexF2": "人指２.L";
							"人指３.L": "L_IndexF3";							"L_IndexF3": "人指３.L";
							"中指１.L": "L_MiddleF1";							"L_MiddleF1": "中指１.L";
							"中指２.L": "L_MiddleF2";							"L_MiddleF2": "中指２.L";
							"中指３.L": "L_MiddleF3";							"L_MiddleF3": "中指３.L";
							--"l_hand_ring_0": "L_Palm";							"L_Palm": "l_hand_ring_0";
							"薬指１.L": "L_RingF1";								"L_RingF1": "薬指１.L";
							"薬指２.L": "L_RingF2";								"L_RingF2": "薬指２.L";
							"薬指３.L": "L_RingF3";								"L_RingF3": "薬指３.L";
							"小指１.L": "L_PinkyF1";							"L_PinkyF1": "小指１.L";
							"小指２.L": "L_PinkyF2";							"L_PinkyF2": "小指２.L";
							"小指３.L": "L_PinkyF3";							"L_PinkyF3": "小指３.L";
							"ダミー.L": "L_WeaponHand";							"L_WeaponHand": "ダミー.L";
							default: objSelected[i].name	
						)
					) else if boneRenameValue == "DMC5 <--> SF6" then (
						do_continue = false
						local newName = case objSelected[i].name of --DMC5 vs SF6
						(
							"Root": "root";									"root": "Root";
							--"Move": "Hip"; 									"Hip": "Move";
							"C_Hip": "Hip"; 								"Hip": "C_Hip";
							--"C_Waist": "Waist"; 							"Waist": "C_Waist";
							"C_Spine1": "Waist"; 							"Waist": "C_Spine1";
							"C_Spine2": "Chest";							"Chest": "C_Spine2";
							"C_Neck": "Neck";								"Neck": "C_Neck";
							"C_Neck1": "Neck_Middle";						"Neck_Middle": "C_Neck1";
							"C_Head": "Head";								"Head": "C_Head";
							"R_Index1": "R_IndexF1";						"R_IndexF1": "R_Index1";
							"R_Index2": "R_IndexF2";						"R_IndexF2": "R_Index2";
							"R_Index3": "R_IndexF3";						"R_IndexF3": "R_Index3";
							"R_Middle1": "R_MiddleF1";						"R_MiddleF1": "R_Middle1";
							"R_Middle2": "R_MiddleF2";						"R_MiddleF2": "R_Middle2";
							"R_Middle3": "R_MiddleF3";						"R_MiddleF3": "R_Middle3";
							"R_Ring1": "R_RingF1";							"R_RingF1": "R_Ring1";
							"R_Ring2": "R_RingF2";							"R_RingF2": "R_Ring2";
							"R_Ring3": "R_RingF3";							"R_RingF3": "R_Ring3";
							"R_Pinky1": "R_PinkyF1";						"R_PinkyF1": "R_Pinky1";
							"R_Pinky2": "R_PinkyF2";						"R_PinkyF2": "R_Pinky2";
							"R_Pinky3": "R_PinkyF3";						"R_PinkyF3": "R_Pinky3";
							"L_Index1": "L_IndexF1";						"L_IndexF1": "L_Index1";
							"L_Index2": "L_IndexF2";						"L_IndexF2": "L_Index2";
							"L_Index3": "L_IndexF3";						"L_IndexF3": "L_Index3";
							"L_Middle1": "L_MiddleF1";						"L_MiddleF1": "L_Middle1";
							"L_Middle2": "L_MiddleF2";						"L_MiddleF2": "L_Middle2";
							"L_Middle3": "L_MiddleF3";						"L_MiddleF3": "L_Middle3";
							"L_Ring1": "L_RingF1";							"L_RingF1": "L_Ring1";
							"L_Ring2": "L_RingF2";							"L_RingF2": "L_Ring2";
							"L_Ring3": "L_RingF3";							"L_RingF3": "L_Ring3";
							"L_Pinky1": "L_PinkyF1";						"L_PinkyF1": "L_Pinky1";
							"L_Pinky2": "L_PinkyF2";						"L_PinkyF2": "L_Pinky2";
							"L_Pinky3": "L_PinkyF3";						"L_PinkyF3": "L_Pinky3";
							"L_Ankle": "L_Foot_twist";						"L_Foot_twist": "L_Ankle";
							"R_Ankle": "R_Foot_twist";						"R_Foot_twist": "R_Ankle";
							"L_Knee": "L_Shin";								"L_Shin": "L_Knee";
							"R_Knee": "R_Shin";								"R_Shin": "R_Knee";
							--"L_Metatarsal": "L_Toe";						"L_Toe": "L_Metatarsal";
							--"R_Metatarsal": "R_Toe";						"R_Toe": "R_Metatarsal";
							default: objSelected[i].name	
						)
					) else	(
						local newName = case objSelected[i].name of --RE2R/RE3R vs RE7/RE8/DMC5 (shared)
						(
							"COG": "Hip"; 										"Hip": "COG";
							"head": "Head";										"Head": "head";
							"l_leg_femur": "L_Thigh";							"L_Thigh":"l_leg_femur";
							"l_leg_tibia": "L_Shin"; 							"L_Shin": "l_leg_tibia";
							"l_leg_ankle": "L_Foot";							"L_Foot": "l_leg_ankle";
							"l_leg_femur_twist_1_H": "L_Thigh_twist_SR"; 		"L_Thigh_twist_SR": "l_leg_femur_twist_1_H";
							"r_leg_femur": "R_Thigh";							"R_Thigh":"r_leg_femur";
							"r_leg_tibia": "R_Shin"; 							"R_Shin": "r_leg_tibia";
							"r_leg_ankle": "R_Foot";							"R_Foot": "r_leg_ankle";
							"r_leg_femur_twist_1_H": "R_Thigh_twist_SR";		"R_Thigh_twist_SR": "r_leg_femur_twist_1_H";
							"r_arm_clavicle": "R_Shoulder";						"R_Shoulder": "r_arm_clavicle";
							"r_arm_humerus": "R_UpperArm";						"R_UpperArm": "r_arm_humerus";
							"r_arm_radius": "R_Forearm";						"R_Forearm": "r_arm_radius";
							"r_arm_wrist": "R_Hand";							"R_Hand": "r_arm_wrist";
							"r_arm_humerus_twist_2_H": "R_UpperArm_twist_SR";	"R_UpperArm_twist_SR": "r_arm_humerus_twist_2_H";
							"l_arm_clavicle": "L_Shoulder";						"L_Shoulder": "l_arm_clavicle";
							"l_arm_humerus": "L_UpperArm";						"L_UpperArm": "l_arm_humerus";
							"l_arm_radius": "L_Forearm";						"L_Forearm": "l_arm_radius";
							"l_arm_wrist": "L_Hand";							"L_Hand": "l_arm_wrist";
							"l_arm_humerus_twist_2_H": "L_UpperArm_twist_SR";	"L_UpperArm_twist_SR": "l_arm_humerus_twist_2_H";
							"r_hand_thumb_0": "R_Thumb1";						"R_Thumb1": "r_hand_thumb_0";
							"r_hand_thumb_1": "R_Thumb2";						"R_Thumb2": "r_hand_thumb_1";
							"r_hand_thumb_2": "R_Thumb3";						"R_Thumb3": "r_hand_thumb_2";
							"r_hand_index_0": "R_IndexF1";						"R_IndexF1": "r_hand_index_0";
							"r_hand_index_1": "R_IndexF2";						"R_IndexF2": "r_hand_index_1";
							"r_hand_index_2": "R_IndexF3";						"R_IndexF3": "r_hand_index_2";
							"r_hand_middle_0": "R_MiddleF1";					"R_MiddleF1": "r_hand_middle_0";
							"r_hand_middle_1": "R_MiddleF2";					"R_MiddleF2": "r_hand_middle_1";
							"r_hand_middle_2": "R_MiddleF3";					"R_MiddleF3": "r_hand_middle_2";
							"r_hand_ring_0": "R_Palm";							"R_Palm": "r_hand_ring_0";
							"r_hand_ring_1": "R_RingF1";						"R_RingF1": "r_hand_ring_1";
							"r_hand_ring_2": "R_RingF2";						"R_RingF2": "r_hand_ring_2";
							"r_hand_ring_3": "R_RingF3";						"R_RingF3": "r_hand_ring_3";
							"r_hand_little_1": "R_PinkyF1";						"R_PinkyF1": "r_hand_little_1";
							"r_hand_little_2": "R_PinkyF2";						"R_PinkyF2": "r_hand_little_2";
							"r_hand_little_3": "R_PinkyF3";						"R_PinkyF3": "r_hand_little_3";
							"r_weapon": "R_WeaponHand";							"R_WeaponHand": "r_weapon";
							"l_hand_thumb_0": "L_Thumb1";						"L_Thumb1": "l_hand_thumb_0";
							"l_hand_thumb_1": "L_Thumb2";						"L_Thumb2": "l_hand_thumb_1";
							"l_hand_thumb_2": "L_Thumb3";						"L_Thumb3": "l_hand_thumb_2";
							"l_hand_index_0": "L_IndexF1";						"L_IndexF1": "l_hand_index_0";
							"l_hand_index_1": "L_IndexF2";						"L_IndexF2": "l_hand_index_1";
							"l_hand_index_2": "L_IndexF3";						"L_IndexF3": "l_hand_index_2";
							"l_hand_middle_0": "L_MiddleF1";					"L_MiddleF1": "l_hand_middle_0";
							"l_hand_middle_1": "L_MiddleF2";					"L_MiddleF2": "l_hand_middle_1";
							"l_hand_middle_2": "L_MiddleF3";					"L_MiddleF3": "l_hand_middle_2";
							"l_hand_ring_0": "L_Palm";							"L_Palm": "l_hand_ring_0";
							"l_hand_ring_1": "L_RingF1";						"L_RingF1": "l_hand_ring_1";
							"l_hand_ring_2": "L_RingF2";						"L_RingF2": "l_hand_ring_2";
							"l_hand_ring_3": "L_RingF3";						"L_RingF3": "l_hand_ring_3";
							"l_hand_little_1": "L_PinkyF1";						"L_PinkyF1": "l_hand_little_1";
							"l_hand_little_2": "L_PinkyF2";						"L_PinkyF2": "l_hand_little_2";
							"l_hand_little_3": "L_PinkyF3";						"L_PinkyF3": "l_hand_little_3";
							"l_weapon": "L_WeaponHand";							"L_WeaponHand": "l_weapon";
							default: objSelected[i].name	
						)
						if do_continue then (
							if BoneRenameValue == "RE2 <--> RE8" then ( --RE2R/RE3R vs RE8 
								newName = case objSelected[i].name of
								(
									"spine_0": "Spine_0"; 								"Spine_0": "spine_0";
									"spine_1": "Spine_1"; 								"Spine_1": "spine_1";
									"spine_2": "Spine_2";								"Spine_2": "spine_2";
									"neck_0": "Neck_0";									"Neck_0": "neck_0";
									"neck_1": "Neck_1";									"Neck_1": "neck_1";
									"l_leg_ball": "L_Toe";								"L_Toe": "l_leg_ball";
									"r_leg_ball": "R_Toe";								"R_Toe": "r_leg_ball";
									"l_leg_ballEnd": "L_ToeEnd";						"L_ToeEnd": "l_leg_ballEnd";
									"r_leg_ballEnd": "R_ToeEnd";						"R_ToeEnd": "r_leg_ballEnd";
									
									"r_serratusA_muscle": "R_serratusA_muscle";			"R_serratusA_muscle": "r_serratusA_muscle";
									"l_serratusA_muscle": "L_serratusA_muscle";			"L_serratusA_muscle": "l_serratusA_muscle";
									
									"r_trapA_muscle": "R_trapA_muscle";					"R_trapA_muscle": "r_trapA_muscle";
									"l_trapA_muscle": "L_trapA_muscle";					"L_trapA_muscle": "l_trapA_muscle";
									
									"r_latA_muscle": "R_latA_muscle";					"R_latA_muscle": "r_latA_muscle";
									"l_latA_muscle": "L_latA_muscle";					"L_latA_muscle": "l_latA_muscle";
									
									"r_pecB_muscle": "R_pecB_muscle";					"R_pecB_muscle": "r_pecB_muscle";
									"l_pecB_muscle": "L_pecB_muscle";					"L_pecB_muscle": "l_pecB_muscle";
									
									"r_pecA_muscle": "R_pecA_muscle";					"R_pecA_muscle": "r_pecA_muscle";
									"l_pecA_muscle": "L_pecA_muscle";					"L_pecA_muscle": "l_pecA_muscle";
									
									"l_deltFront_muscle": "L_deltFront_muscle";			"L_deltFront_muscle": "l_deltFront_muscle";
									"l_deltBack_muscle": "L_deltBack_muscle";			"L_deltBack_muscle": "l_deltBack_muscle";
									"l_deltUp_muscle": "L_deltUp_muscle";				"L_deltUp_muscle": "l_deltUp_muscle";
									"r_deltFront_muscle": "R_deltFront_muscle";			"R_deltFront_muscle": "r_deltFront_muscle";
									"r_deltUp_muscle": "R_deltUp_muscle";				"R_deltUp_muscle": "r_deltUp_muscle";
									"r_deltBack_muscle": "R_deltBack_muscle";			"R_deltBack_muscle": "r_deltBack_muscle";
									
									"r_arm_humerus_twist_0_H": "R_UpperArm_Twist_3";	"R_UpperArm_Twist_0": "r_arm_humerus_twist_3_H";
									"r_arm_humerus_twist_1_H": "R_UpperArm_Twist_2";	"R_UpperArm_Twist_1": "r_arm_humerus_twist_2_H";
									"r_arm_humerus_twist_2_H": "R_UpperArm_Twist_1";	"R_UpperArm_Twist_2": "r_arm_humerus_twist_1_H";
									"r_arm_humerus_twist_3_H": "R_UpperArm_Twist_0";	"R_UpperArm_Twist_3": "r_arm_humerus_twist_0_H";
									"l_arm_humerus_twist_0_H": "L_UpperArm_Twist_3";	"L_UpperArm_Twist_0": "l_arm_humerus_twist_3_H";
									"l_arm_humerus_twist_1_H": "L_UpperArm_Twist_2";	"L_UpperArm_Twist_1": "l_arm_humerus_twist_2_H";
									"l_arm_humerus_twist_2_H": "L_UpperArm_Twist_1";	"L_UpperArm_Twist_2": "l_arm_humerus_twist_1_H";
									"l_arm_humerus_twist_3_H": "L_UpperArm_Twist_0";	"L_UpperArm_Twist_3": "l_arm_humerus_twist_0_H";
									
									"r_arm_radius_twist_0_H": "R_Forearm_Twist_0";		"R_Forearm_Twist_0": "r_arm_radius_twist_0_H";
									"r_arm_radius_twist_1_H": "R_Forearm_Twist_1";		"R_Forearm_Twist_1": "r_arm_radius_twist_1_H";
									"r_arm_radius_twist_2_H": "R_Forearm_Twist_2";		"R_Forearm_Twist_2": "r_arm_radius_twist_2_H";
									"r_arm_radius_twist_3_H": "R_Forearm_Twist_3";		"R_Forearm_Twist_3": "r_arm_radius_twist_3_H";
									"l_arm_radius_twist_0_H": "L_Forearm_Twist_0";		"L_Forearm_Twist_0": "l_arm_radius_twist_0_H";
									"l_arm_radius_twist_1_H": "L_Forearm_Twist_1";		"L_Forearm_Twist_1": "l_arm_radius_twist_1_H";
									"l_arm_radius_twist_2_H": "L_Forearm_Twist_2";		"L_Forearm_Twist_2": "l_arm_radius_twist_2_H";
									"l_arm_radius_twist_3_H": "L_Forearm_Twist_3";		"L_Forearm_Twist_3": "l_arm_radius_twist_3_H";
									
									"l_leg_femur_twist_0_H": "L_Thigh_Twist_2"; 		"L_Thigh_Twist_2": "l_leg_femur_twist_0_H";
									"l_leg_femur_twist_1_H": "L_Thigh_Twist_1"; 		"L_Thigh_Twist_1": "l_leg_femur_twist_1_H";
									"l_leg_femur_twist_2_H": "L_Thigh_Twist_0"; 		"L_Thigh_Twist_0": "l_leg_femur_twist_2_H";
									"r_leg_femur_twist_0_H": "R_Thigh_Twist_2"; 		"R_Thigh_Twist_2": "r_leg_femur_twist_0_H";
									"r_leg_femur_twist_1_H": "R_Thigh_Twist_1"; 		"R_Thigh_Twist_1": "r_leg_femur_twist_1_H";
									"r_leg_femur_twist_2_H": "R_Thigh_Twist_0"; 		"R_Thigh_Twist_0": "r_leg_femur_twist_2_H";
									
									"r_leg_tibia_twist_0_H": "R_Shin_Twist_0"; 			"R_Shin_Twist_0": "r_leg_tibia_twist_0_H";
									"l_leg_tibia_twist_0_H": "L_Shin_Twist_0"; 			"L_Shin_Twist_0": "l_leg_tibia_twist_0_H";
									"r_leg_tibia_twist_1_H": "R_Shin_Twist_1"; 			"R_Shin_Twist_1": "r_leg_tibia_twist_1_H";
									"l_leg_tibia_twist_1_H": "L_Shin_Twist_1"; 			"L_Shin_Twist_1": "l_leg_tibia_twist_1_H";
									"r_leg_tibia_twist_2_H": "R_Shin_Twist_2"; 			"R_Shin_Twist_2": "r_leg_tibia_twist_2_H";
									"l_leg_tibia_twist_2_H": "L_Shin_Twist_2"; 			"L_Shin_Twist_2": "l_leg_tibia_twist_2_H";
									
									"r_leg_front_muscleOffset": "R_leg_front_muscleOffset"; 	"R_leg_front_muscleOffset": "r_leg_front_muscleOffset";
									"r_leg_back_muscleOffset": "R_leg_back_muscleOffset"; 		"R_leg_front_muscleOffset": "r_leg_front_muscleOffset";
									"r_leg_side_muscleOffset": "R_leg_side_muscleOffset"; 		"R_leg_front_muscleOffset": "r_leg_front_muscleOffset";
									
									"l_leg_front_muscleOffset": "L_leg_front_muscleOffset"; 	"L_leg_front_muscleOffset": "l_leg_front_muscleOffset";
									"l_leg_back_muscleOffset": "L_leg_back_muscleOffset"; 		"L_leg_front_muscleOffset": "l_leg_front_muscleOffset";
									"l_leg_side_muscleOffset": "L_leg_side_muscleOffset"; 		"L_leg_front_muscleOffset": "l_leg_front_muscleOffset";
									
									"l_hand_little_0": "L_hand_little_0"; 						"L_hand_little_0": "l_hand_little_0";
									"r_hand_little_0": "R_hand_little_0"; 						"R_hand_little_0": "r_hand_little_0";
									default: newName
								) 
							) else ( --RE2R/RE3R <-> DMC5
								newName = case objSelected[i].name of 
								(
									"setProp_B_00": "WeaponConst";						"WeaponConst": "setProp_B_00";
									"spine_0": "Waist"; 								"Waist": "spine_0";
									"spine_1": "Stomach"; 								"Stomach": "spine_1";
									"spine_2": "Chest";									"Chest": "spine_2";
									"neck_0": "Neck";									"Neck": "neck_0";
									"neck_1": "Neck_Middle";							"Neck_Middle": "neck_1";
									"r_arm_radius_twist_1_H": "R_Hand_twistX3_SR";		"R_Hand_twistX3_SR": "r_arm_radius_twist_1_H";
									"r_arm_radius_twist_2_H": "R_Hand_twistX2_SR";		"R_Hand_twistX2_SR": "r_arm_radius_twist_2_H";
									"r_arm_radius_twist_3_H": "R_Hand_twistX1_SR";		"R_Hand_twistX1_SR": "r_arm_radius_twist_3_H";
									"l_arm_radius_twist_1_H": "L_Hand_twistX3_SR";		"L_Hand_twistX3_SR": "l_arm_radius_twist_1_H";
									"l_arm_radius_twist_2_H": "L_Hand_twistX2_SR";		"L_Hand_twistX2_SR": "l_arm_radius_twist_2_H";
									"l_arm_radius_twist_3_H": "L_Hand_twistX1_SR";		"L_Hand_twistX1_SR": "l_arm_radius_twist_3_H";
									"l_leg_ballEnd": "L_Toe";							"L_Toe": "l_leg_ballEnd";
									"r_leg_ballEnd": "R_Toe";							"R_Toe": "r_leg_ballEnd";
									default: newName
								)
							)
						)
					)
					if objSelected[i].name != newName then (
						appendIfUnique bones objSelected[i] 				
						if objSelected[i].parent != undefined then appendIfUnique bones objSelected[i].parent 
					)
					objSelected[i].name = newName
				)
				
				--fix parenting
				if Chk_Reparent.checked and BoneRenameValue == "RE2 <--> RE8" then (
					local boneNames = (for i = 1 to objSelected.count collect objSelected[i].name)
					for i = 1 to objSelected.count do (
						local newParentId = case objSelected[i].name of
						(
							"R_Shin_Twist_2": findItem boneNames "R_Shin_Twist_1";					"r_leg_tibia_twist_2_H": findItem boneNames "r_leg_tibia";
							"R_Shin_Twist_1": findItem boneNames "R_Shin_Twist_0";					"r_leg_tibia_twist_1_H": findItem boneNames "r_leg_tibia";
							"L_Shin_Twist_2": findItem boneNames "L_Shin_Twist_1";					"l_leg_tibia_twist_2_H": findItem boneNames "l_leg_tibia";
							"L_Shin_Twist_1": findItem boneNames "L_Shin_Twist_0";					"l_leg_tibia_twist_1_H": findItem boneNames "l_leg_tibia";
							
							"R_Thigh_Twist_2": findItem boneNames "R_Thigh_Twist_1";				"r_leg_femur_twist_0_H": findItem boneNames "r_leg_femur";
							"R_Thigh_Twist_1": findItem boneNames "R_Thigh_Twist_0";				"r_leg_femur_twist_1_H": findItem boneNames "r_leg_femur";
							"L_Thigh_Twist_2": findItem boneNames "L_Thigh_Twist_1";				"l_leg_femur_twist_0_H": findItem boneNames "l_leg_femur";
							"L_Thigh_Twist_1": findItem boneNames "L_Thigh_Twist_0";				"l_leg_femur_twist_1_H": findItem boneNames "l_leg_femur";
							
							"R_Forearm_Twist_3": findItem boneNames "R_Forearm_Twist_2";			"r_arm_radius_twist_3_H": findItem boneNames "r_arm_radius";
							"R_Forearm_Twist_2": findItem boneNames "R_Forearm_Twist_1";			"r_arm_radius_twist_2_H": findItem boneNames "r_arm_radius";
							"R_Forearm_Twist_1": findItem boneNames "R_Forearm_Twist_0";			"r_arm_radius_twist_1_H": findItem boneNames "r_arm_radius";
							"L_Forearm_Twist_3": findItem boneNames "L_Forearm_Twist_2";			"l_arm_radius_twist_3_H": findItem boneNames "l_arm_radius";
							"L_Forearm_Twist_2": findItem boneNames "L_Forearm_Twist_1";			"l_arm_radius_twist_2_H": findItem boneNames "l_arm_radius";
							"L_Forearm_Twist_1": findItem boneNames "L_Forearm_Twist_0";			"l_arm_radius_twist_1_H": findItem boneNames "l_arm_radius";
							
							"R_UpperArm_Twist_3": findItem boneNames "R_UpperArm_Twist_2";			"r_arm_humerus_twist_3_H": findItem boneNames "r_arm_humerus";
							"R_UpperArm_Twist_2": findItem boneNames "R_UpperArm_Twist_1";			"r_arm_humerus_twist_2_H": findItem boneNames "r_arm_humerus";
							"R_UpperArm_Twist_1": findItem boneNames "R_UpperArm_Twist_0";			"r_arm_humerus_twist_1_H": findItem boneNames "r_arm_humerus";
							"L_UpperArm_Twist_3": findItem boneNames "L_UpperArm_Twist_2";			"l_arm_humerus_twist_3_H": findItem boneNames "l_arm_humerus";
							"L_UpperArm_Twist_2": findItem boneNames "L_UpperArm_Twist_1";			"l_arm_humerus_twist_2_H": findItem boneNames "l_arm_humerus";
							"L_UpperArm_Twist_1": findItem boneNames "L_UpperArm_Twist_0";			"l_arm_humerus_twist_1_H": findItem boneNames "l_arm_humerus";
							
							"R_PinkyF1": findItem boneNames "R_Palm";								"r_hand_little_1": findItem boneNames "r_hand_little_0";
							"R_hand_little_0": findItem boneNames "R_Palm"; 						"r_hand_little_0": findItem boneNames "r_arm_wrist"; 
							
							"L_PinkyF1": findItem boneNames "L_Palm";								"l_hand_little_1": findItem boneNames "l_hand_little_0";
							"L_hand_little_0": findItem boneNames "L_Palm"; 						"l_hand_little_0": findItem boneNames "l_arm_wrist"; 
							
							"R_leg_front_muscleOffset": findItem boneNames "R_Thigh";				"r_leg_front_muscleOffset": findItem boneNames "hips";
							"R_leg_side_muscleOffset": findItem boneNames "R_Thigh";				"r_leg_side_muscleOffset": findItem boneNames "hips";
							"R_leg_back_muscleOffset": findItem boneNames "R_Thigh";				"r_leg_back_muscleOffset": findItem boneNames "hips";
							
							"L_leg_front_muscleOffset": findItem boneNames "L_Thigh";				"l_leg_front_muscleOffset": findItem boneNames "hips";
							"L_leg_side_muscleOffset": findItem boneNames "L_Thigh";				"l_leg_side_muscleOffset": findItem boneNames "hips";
							"L_leg_back_muscleOffset": findItem boneNames "L_Thigh";				"l_leg_back_muscleOffset": findItem boneNames "hips";
							
							"L_Thigh": findItem boneNames "Hip";									"l_leg_femur": findItem boneNames "hips";
							"R_Thigh": findItem boneNames "Hip";									"r_leg_femur": findItem boneNames "hips";
							
							default: 0;
						)
						
						if newParentId > 0 then (
							format "Changing parentId of % to %\n" objSelected[i].name objSelected[newParentId].name
							objSelected[i].parent = objSelected[newParentId]
						)
						if false then --try to fix RE2 vs RE8 ankle difference
							if objSelected[i].name == "l_leg_ball" or objSelected[i].name == "r_leg_ball" or objSelected[i].name == "R_Toe" or objSelected[i].name == "L_Toe" then (
								childBones = for childBone in objSelected[i].children collect #(childBone, childBone.pos)
								oldPos = objSelected[i].pos
								--for childBone in childBones do childBone[1].parent = undefined
								format "ChildBones1 : % %\n" childBones childBones.count
								if objSelected[i].name == "l_leg_ball" or objSelected[i].name == "r_leg_ball" then 
									objSelected[i].transform.controller.value *= (matrix3 [1,0,0][0,0,-1][0,1,0][0,0,0])
								else
									objSelected[i].transform.controller.value *= (matrix3 [1,0,0] [0,0,1] [0,-1,0] [0,0,0])
								objSelected[i].pos = oldPos
								--for childBone in childBones do ( childBone[1].parent = objSelected[i])
								--for childBone in childBones do ( childBone[1].pos = childBone[2])
								format "ChildBones2 : % %\n" childBones childBones.count
							)
					)
				)
				
				select bones
				max hide inv
			)
		)
		
		on SetUprightButton pressed do (
			local objSelected = selection as array
			with undo on (
				for i = 1 to objSelected.count do (
					if (objSelected[i].parent == undefined) and (superclassof objSelected[i] == Helper or classof objSelected[i] == BoneGeometry) then (
						/*local delta = inverse objSelected[i].transform
						local tempPos = objSelected[i].transform.pos
						delta.pos = [0,0,0]	
						objSelected[i].transform *= delta * (matrix3 [1,0,0] [0,0,1] [0,-1,0] [0,0,0])
						objSelected[i].pos = tempPos*/
						objSelected[i].scale.controller.value = [1, 1, 1]
						exit
					)
				)
			)
		)
		
		on FixHeightButton rightclick do ( --flips along X axis
			local objSelected = selection as array
			with undo on (
				for i = 1 to objSelected.count do 
					if (objSelected[i].parent == undefined) and (superclassof objSelected[i] == Helper or classof objSelected[i] == BoneGeometry) then (
						local tempPos = objSelected[i].pos; 
						objSelected[i].transform *= (matrix3 [-1,0,0] [0,1,0] [0,0,1] [0,0,0]); 
						objSelected[i].pos = tempPos
						exit
					)
			)
		)
		on SetUprightButton rightclick do ( --flips along Y axis
			local objSelected = selection as array
			with undo on (
				for i = 1 to objSelected.count do 
					if (objSelected[i].parent == undefined) and (superclassof objSelected[i] == Helper or classof objSelected[i] == BoneGeometry) then (
						local tempPos = objSelected[i].pos; 
						objSelected[i].transform *= (matrix3 [1,0,0] [0,-1,0] [0,0,1] [0,0,0]); 
						objSelected[i].pos = tempPos
						exit
					)
			)
		)
		on ReParentButton rightclick do ( --flips along Z axis
			local objSelected = selection as array
			with undo on (
				for i = 1 to objSelected.count do 
					if (objSelected[i].parent == undefined) and (superclassof objSelected[i] == Helper or classof objSelected[i] == BoneGeometry) then (
						local tempPos = objSelected[i].pos; 
						objSelected[i].transform *= (matrix3 [1,0,0] [0,1,0] [0,0,-1] [0,0,0]); 
						objSelected[i].pos = tempPos
						exit
					)
			)
		)
		
		on FixHeightButton pressed do (
			local objSelected = selection as array
			local rootBone = -1 
			for i = 1 to objSelected.count do if objSelected[i].name == "root" then ( rootBone = objSelected[i]; exit )
			with undo on (
				if rootBone != -1 then with animate on (
					for child in rootBone.children do (
						if superclassof child == Helper or classof child == BoneGeometry then (
							for kf = 1 to (numKeys child.pos.controller) do ( at time (getKeyTime child.pos.controller kf) ( child.pos.controller.value.y += rootBone.pos.controller.value.z ) )
						)
					)
					for kf = 1 to (numKeys rootBone.pos.controller) do ( 
						at time (getKeyTime rootBone.pos.controller kf) ( rootBone.pos.controller.value.z = 0 )
					)
				)
			)
		)
		
		on CloneBoneButton pressed do (
			local objSelected = selection as array
			if objSelected.count != 2 then local doReturn = true 
			for obj in objSelected do if (superclassof obj != Helper and classof obj != BoneGeometry) then local doReturn = true 
			if doReturn != undefined then ( messagebox "Select the source bone first, then the target"; return 0)		
			local source = objSelected[1]; local target = objSelected[2]; local copyNodes = #()
			maxOps.cloneNodes source cloneType:#copy newNodes:&copyNodes #nodialog
			local newTarget = copyNodes[1]
			newTarget.transform = target.transform
			newTarget.name = target.name
			newTarget.parent = target.Parent
			select newTarget
			target.isNodeHidden = true
			messageBox "Complete!"
		)
	)
	createDialog motlistMod 180 480
)