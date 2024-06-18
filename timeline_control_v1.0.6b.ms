/*
TimeLine Control v1.0.6c
-------------
by Dim_Walker (dw.deedoubleu@gmail.com)
Based on Time_Controlv0.1 by Ayoub Mahmoudi.

Updated Feb 11 2022 by alphaZomega
-------------
Please visit this page:
http://www.scriptspot.com/3ds-max/scripts/timeline-control
for version history and additional info.
*/

global TC
global timerange
global ddl_range2
(
	struct TCstructDef	
	(
		ver = "1.0.6",
		Autocomplete = false,
		hitTest = false,
		ddl_range2,
		sp_start,
		sp_end,
		sp_move,
		new_name_rol,
		name_rol,
		settings,
		insertSettings,
		fn insert_frames = 
		(
			stopAnimation()
			local framesToInsert = (TC.insertSettings.ins_etNumFrames.text as integer)
			with undo on (
				local objSelected = selection as array
				for obj in objselected where superclassof obj == BoneGeometry or superclassof obj == Helper do (
					deselectkeys 
					selectKeys obj.pos.controller (getKeyIndex obj.pos.controller sp_end.value) (numkeys obj.pos.controller + framesToInsert)
					selectKeys obj.rotation.controller (getKeyIndex obj.rotation.controller sp_end.value) (numkeys obj.rotation.controller + framesToInsert)
					selectKeys obj.scale.controller (getKeyIndex obj.scale.controller sp_end.value) ((numkeys obj.scale.controller) + framesToInsert)
					movekeys obj.pos.controller framesToInsert #selection
					movekeys obj.rotation.controller framesToInsert #selection
					movekeys obj.scale.controller framesToInsert #selection
				)
				
				if sp_start.value - sp_end.value+framesToInsert != 0 then
					try (animationRange = interval sp_start.value (sp_end.value+framesToInsert)) catch (undefined)
				
				TC.insRanges (TC.insertSettings.ins_etNumFrames.text as integer)
			)
			try(destroyDialog ins_dialog)catch()
		),

		fn export_fbx = (
			--FbxExporterGetParam ScaleFactor
			pluginManager.loadClass FbxExporter
			FbxExporterSetParam "ScaleFactor"					(TC.settings.xprt_etScaleFactor.text as float)
			FbxExporterSetParam "Cameras"						false
			FbxExporterSetParam "Animation"						true
			FbxExporterSetParam "SmoothingGroups"				TC.settings.xprt_SmoothingGroups.state
			FbxExporterSetParam "BakeAnimation"					TC.settings.xprt_BakeAnimation.state
			--FbxExporterSetParam "BakeFrameStart"				TC.sp_start.value
			--FbxExporterSetParam "BakeFrameEnd"				TC.sp_end.value
			FbxExporterSetParam "BakeFrameStep"					1
			FbxExporterSetParam "BakeResampleAnimation"			true
			FbxExporterSetParam "FileVersion"					"FBX201200"
			FbxExporterSetParam "EmbedTextures"					false
			FbxExporterSetParam "Skin"							true
			FbxExporterSetParam "UpAxis"						TC.settings.xprt_ddlUpAxis.selected
			FbxExporterSetParam "NormalsPerPoly"				TC.settings.xprt_NormalsPerPoly.state
			FbxExporterSetParam "ShowWarnings"					false
			FbxExporterSetParam "ConvertUnit"					"in"
			--FBXExporterSetParam "PushSettings"

			saveFilePath = (getSavePath initialDir:maxFilePath) + "\\"

			end = TC.ddl_range2.items.count-1
			--format "end - %\n" end
			thisFileName = getFilenameFile maxFilename
			for i = 1 to end do (
				fullSaveName = saveFilePath + thisFileName + "@" + (filterString (TC.ddl_range2.items.item[i]) " ")[1] + ".fbx"
				FbxExporterSetParam "BakeFrameStart"				(((filterString (TC.ddl_range2.items.item[i]) " ")[3]) as integer)
				FbxExporterSetParam "BakeFrameEnd"					(((filterString (TC.ddl_range2.items.item[i]) " ")[4]) as integer)
				--format "saveFilePath - %\n" saveFilePath
				--format "fullSaveName - %\n" fullSaveName
				--format "==================================================\n"
				exportFile fullSaveName #noPrompt selectedOnly:true	
			)
		),
					
		fn setTimeRange = (
				stopAnimation()
				animationRange = interval sp_start.value sp_end.value
		),
				
		fn updateSp_Values = (
			sp_start.value = (animationRange.start.frame as integer)   
			sp_end.value = (animationRange.end.frame as integer)
		),
				
		fn goToPrev_Key =	(
			Previous_Key = trackbar.getPreviousKeyTime()
			if selection.count != undefined and Previous_Key != undefined do sliderTime = Previous_Key
		),
				
		fn goToNext_Key =	(
			Next_Key = trackbar.getNextKeyTime()
			if selection.count != undefined and Next_Key != undefined do sliderTime = Next_Key
		),

		fn load_Range2 SelectedItem = (
			if SelectedItem != undefined do	(
				rangeArray = filterString SelectedItem " "
				Start_range = rangeArray[(rangeArray.count)-1] as integer
				End_range = rangeArray[(rangeArray.count)] as integer
				if Start_range != undefined and End_range != undefined and End_range - Start_range > 0 do
					animationRange = interval Start_range End_range
				redrawViews()
			)	
		),
		--  =====================================================================
		fn comboAsArray = (
			Range_items = #()
			for i = 0 to TC.ddl_range2.items.count-1 do (
				append Range_items TC.ddl_range2.items.item[i]
			)
			return Range_items
		),

		fn fileOpen = (
			if (maxfilename != "" and TC.INIexist()) then	(
				TC.updateSp_Values()
				Range_items2 = execute (TC.readINI "Data" "Ranges")
				if classof Range_items2 == Array do (
					TC.ddl_range2.items.clear()
					TC.ddl_range2.items.addrange Range_items2
				)
				
				Range_selection2 = execute (TC.readINI "Data" "LastSelection")
				if classof Range_selection2 == Integer do TC.ddl_range2.SelectedIndex = Range_selection2
				TC.load_Range2 (TC.ddl_range2.SelectedItem)
			) else	(
				TC.ddl_range2.items.clear()
			)
			TC.updateSp_Move()
		),

		fn moveListItem val =	(
			if TC.INIexist() and TC.ddl_range2.SelectedIndex != -1 then (
				oldPos = TC.ddl_range2.SelectedIndex
		--	spinner invert and bounds
				if val > oldPos and oldPos > 0 then (
						newPos = (oldPos - 1)
				) else if val < oldPos and oldPos < (TC.sp_move.range.y-1) then (
						newPos = (oldPos + 1)
				) else (
					newPos = oldPos
				)
				
				item = TC.ddl_range2.SelectedItem
				TC.ddl_range2.items.Removeat oldPos
				TC.ddl_range2.items.Insert newPos item
				
				TC.ddl_range2.SelectedIndex=newPos
				TC.sp_move.range.z = newPos
				TC.fileSave()
			) else (
			TC.sp_move.value = TC.ddl_range2.SelectedIndex
			)
		),
			
		fn updateSp_Move = (
			if (TC.ddl_range2.SelectedIndex != -1) and (TC.ddl_range2.items.count > 1) then (
				TC.sp_move.value = (TC.ddl_range2.SelectedIndex)
				TC.sp_move.range.y = (TC.ddl_range2.items.count)
			) else (
				TC.sp_move.range = [-1,1,1]
			)
		),

		fn uniqueName name_ra sw = (
			local a
			Anim_Range = (TC.sp_start.value as string + " " + TC.sp_end.value as string)
			range_list = comboAsArray()
			a = ( name_ra + "   : " + Anim_Range )
			if not TC.ddl_range2.items.Contains a then (
				case of	(
					(sw == 1):	(
							append range_list a
							TC.ddl_range2.items.clear()
							TC.ddl_range2.items.addrange range_list
							TC.ddl_range2.SelectedIndex = range_list.count - 1
							TC.updateSp_Move()
							try(destroyDialog TC.name_rol)catch()
						)
					(sw == 2):	(
							TC.ddl_range2.items.set_Item TC.ddl_range2.SelectedIndex a
							try(destroyDialog TC.new_name_rol)catch()
						)
				)
				TC.fileSave()
			) else messagebox "There is Already One With The same Name and The same Range" title:("TimeLine Control v." + TC.ver as string)
		),

		fn readINI section key = (
			thisIniName = substring maxfilename 1 (maxfilename.count-4)+".ini"
			thisIniFullName = getDir #plugcfg + "\\tc\\" + thisIniName
			return (getIniSetting thisIniFullName section key)
		),

		fn fileSave = (
		-- if ranges not empty
			if (TC.ddl_range2.SelectedIndex != -1) then	(
		-- if INI exist add ranges	
				if TC.INIexist() then (
					TC.writeINI "Data" "Ranges" (with printAllElements on (comboAsArray() as string))
					if TC.ddl_range2.SelectedIndex != -1 do TC.writeINI "Data" "LastSelection" (TC.ddl_range2.SelectedIndex as string)
					TC.writeINI "Data" "ListHeight" (TC.ddl_range2.DropDownHeight as string)
					if (classof TC.Autocomplete == BooleanClass) then (
						TC.writeINI "Data" "Autocomplete" (TC.Autocomplete as string)
					) else (
						TC.writeINI "Data" "Autocomplete" "false"
					)
				) else (
		-- if INI not exist add defaults
					--TC.writeINI "Data" "Ranges" "#(\"T" + "   : " + "0 100\")"
					TC.writeINI "Data" "Ranges" (with printAllElements on (comboAsArray() as string))
					TC.writeINI "Data" "LastSelection" "0"
					TC.writeINI "Data" "ListHeight" "400"
					TC.writeINI "Data" "Autocomplete" "false"
				)
			) else	(
				TC.ddl_range2.items.clear()
			)
			TC.updateSp_Move()
		),

		fn writeINI section key val = (
			if (maxfilename != "") do	(
				thisIniName = substring maxfilename 1 (maxfilename.count-4)+".ini"
				thisIniFullName = getDir #plugcfg + "\\tc\\" + thisIniName
				try(setFileAttribute thisIniFullName #readOnly false)catch()
				setIniSetting thisIniFullName section key val
			)
		),

		fn INIexist = (
			thisIniName = substring maxfilename 1 (maxfilename.count-4)+".ini"
			thisIniFullName = getDir #plugcfg + "\\tc\\" + thisIniName
			(getfiles thisIniFullName).count != 0
		),

		fn deleteRange = (
			index = TC.ddl_range2.SelectedIndex
			if index != -1 do (
				TC.ddl_range2.items.Removeat index
				length = TC.ddl_range2.items.count
			)
			if (TC.ddl_range2.SelectedIndex == -1 and length > 0) do TC.ddl_range2.SelectedIndex = length - 1
			if (TC.ddl_range2.SelectedIndex == -1 and length < 1) do (
				TC.ddl_range2.items.clear()
				TC.ddl_range2.Text = ""
			)
			TC.fileSave()
		),


		fn insRanges framesToInsert = (
			if (TC.ddl_range2.SelectedIndex != -1) do (				
				index = TC.ddl_range2.SelectedIndex
				local s = ""
				if index != -1 do (
					local prevSel = TC.ddl_range2.SelectedItem
					local tempRanges = comboAsArray()
					for i=1 to tempRanges.count do (
						local tmp = filterString tempRanges[i] " "
						local startframe = (tmp[3] as integer)
						local endframe = (tmp[4] as integer)
						if i >= index+1 then (
							endframe += framesToInsert
							if i > index+1 then
								startframe += framesToInsert
						)
						tempRanges[i] = (tmp[1]) + " " + (tmp[2]) + " " + (startframe as string) + " " + (endframe as string)
						local ss = ""
						if i == 1 then ss += "\n#(" 
						ss += "\"" + (tempRanges[i] as string) + "\"" 
						if i == tempRanges.count then 
							ss += ")\n" 
						else ss += ",\n"
						s += ss
					)
					objSelected = (selection as array) 
					for obj in objSelected do (SetUserProp obj "TimeLineControl_Frames" s)
					TC.writeINI "Data" "Ranges" (with printAllElements on (tempRanges as string))
					TC.ddl_range2.items.clear()
					TC.ddl_range2.items.addrange tempRanges
					newItemPos = TC.ddl_range2.FindStringExact prevSel
					if newItemPos != -1 do TC.ddl_range2.SelectedIndex = newItemPos
					TC.ddl_range2.Text = tempRanges[index+1]
				)
			) -- end if
		), -- end insRanges

		fn sortRanges frames = (
			if (TC.ddl_range2.SelectedIndex != -1) do (
				fn compareFNFrames v1 v2 =	(
					local d = ((filterString v1 " ")[3]) as integer -((filterString v2 " ")[3]) as integer
					case of	(
						(d < 0.): -1
						(d > 0.): 1
						default: 0
					)
				)
				fn compareFNNames v1 v2 =	(
					local a = ((filterString v1 " ")[1]) as string
					local b = ((filterString v2 " ")[1]) as string
					return (stricmp a b)
				)

				local prevSel = TC.ddl_range2.SelectedItem
				local tempRanges = comboAsArray()
				-- true = frames, false = names
				if frames then qsort tempRanges compareFNFrames else qsort tempRanges compareFNNames
				TC.writeINI "Data" "Ranges" (with printAllElements on (tempRanges as string))
				TC.ddl_range2.items.clear()
				TC.ddl_range2.items.addrange tempRanges
				newItemPos = TC.ddl_range2.FindStringExact prevSel
				if newItemPos != -1 do TC.ddl_range2.SelectedIndex = newItemPos
			) -- end if
		) -- end sortRanges
		
	)
	-- struct end

	--try(cui.UnRegisterDialogBar timerange)catch()
	--try(destroyDialog timerange)catch()
	
-- =========================================================================================================================
--														ROLLOUTS
-- =========================================================================================================================

-- ==================================
--					Timeline Control Settings
-- ==================================
	rollout tc_settings "TC settings"(
		checkbox cb_Autocomplete "Autocomplete" checked:true tooltip:"RangesList Autocomplete" --align:#left across:2 --pos:[820,2]
		spinner sp_listHeight "RangesList height " range:[200,800,400] type:#integer fieldWidth:40 --pos:[488,2]
		group "Debug" ( 
			button bt_openIniDir "open INI folder" height:20 tooltip:"Open INI-Storage Folder" width:140 --align:#right--pos:[948,0]
			button bt_copyList "copy list" tooltip:"copy ranges to clipboard" width:65 across:2 --align:#left
			button bt_pasteList "paste list" tooltip:"paste ranges from clipboard" width:65
			button bt_pasteRevilmaxList "paste Revilmax list" tooltip:"paste ranges from Revilmax \"Load-All\" output in clipboard" width:125 
			--button bt_boneList "import from bone" tooltip:"paste ranges from selected bone" width:65 
			button bt_defini "default INI" height:20 tooltip:"create default INI file" width:140
			
		)

		on tc_settings open do (
			lh = (execute (TC.readINI "Data" "ListHeight"))
			if classof lh == Integer do tc_settings.sp_listHeight.value = lh
			ac = (execute (TC.readINI "Data" "Autocomplete"))
			if classof ac == BooleanClass do tc_settings.cb_Autocomplete.checked = ac
		)
		
		on cb_Autocomplete changed val do (
			TC.Autocomplete = val
			TC.writeINI "Data" "Autocomplete" (val as string)
		)

		on sp_listHeight changed val do (
			TC.ddl_range2.DropDownHeight = val
			TC.writeINI "Data" "ListHeight" (val as string)
		)

		on bt_openIniDir pressed do shellLaunch (getDir #plugcfg + "\\tc") ""
		
		on bt_copyList pressed do setclipboardText (with printAllElements on (TC.comboAsArray() as string))
		on bt_pasteList pressed do	(
			cbtext = (execute (getclipboardText()))
			if classof cbtext == Array do (
				TC.ddl_range2.items.clear()
				TC.ddl_range2.items.addrange cbtext
				TC.ddl_range2.SelectedIndex = 0
				for bone in (selection as array) where (superclassof bone == Helper or superclassof bone == BoneGeometry) do
					SetUserProp bone "TimeLineControl_Frames" (with printAllElements on (TC.comboAsArray() as string))
				
			)
		)
		
		on bt_pasteRevilmaxList pressed do	(
			cbstring = getclipboardText()
			lines = filterString cbstring "\n"
			cbtext = #()
			local nextTime
			for line in lines do (
				line = filterString line ":"
				times = filterString line[2] ","
				lastTime = (times[1] as integer) / TicksPerFrame 
				nextTime = (times[2] as integer) / TicksPerFrame
				if nextTime - lastTime > 1 then 
					nextTime = nextTime - 1
				append cbtext (line[1] + "   : " + (lastTime as string) + " " + (nextTime as string))
			)
			--for line in cbtext do format "%\n" cbtext
			print cbtext
			append cbtext ("[ALL]   : 0 " + (nextTime as string))
			
			
			--cbtext = (execute (cbtext))
			if classof cbtext == Array do (
				
				TC.ddl_range2.items.clear()
				TC.ddl_range2.items.addrange cbtext
				TC.ddl_range2.SelectedIndex = 0
				bones = (selection as array)
				for bone in bones where (superclassof bone == Helper or superclassof bone == BoneGeometry) do
					SetUserProp bone "TimeLineControl_Frames" (with printAllElements on (TC.comboAsArray() as string))
				
			)
		)
		
		/*on bt_boneList pressed do	(
			with printAllElements on (
				for obj in (selection as array) where (superclassof obj == Helper or superclassof obj == BoneGeometry) do  (
					
					if  (GetUserProp obj "TimeLineControl_Frames") != undefined and classof (GetUserProp obj "TimeLineControl_Frames") == Array then (
						local boneFramesList = (GetUserProp obj "TimeLineControl_Frames") as array
						print boneFramesList
						print obj
						TC.ddl_range2.items.clear()
						TC.ddl_range2.items.addrange cbtext
						TC.ddl_range2.SelectedIndex = 0
						for bone in (selection as array) where (superclassof bone == Helper or superclassof bone == BoneGeometry) do
							SetUserProp obj "TimeLineControl_Frames" (with printAllElements on (TC.comboAsArray() as string))
						exit
					)
				)
			)
		)*/
		
		on bt_defini pressed do	(
			TC.writeINI "Data" "Ranges" ("#(\"T   : 0 100\")")
			TC.writeINI "Data" "LastSelection" "0"
			TC.writeINI "Data" "ListHeight" "400"
			TC.writeINI "Data" "Autocomplete" "false"
			TC.fileOpen()
			--TC.ddl_range2.SelectedIndex = 0
			--TC.updateSp_Move()
		)
	)

-- ==================================
--					FBX Export Settings
-- ==================================
	rollout fbx_settings "Export Settings" (
		group "Settings" (
			label xprt_ScaleFactor "ScaleFactor" across:2
			edittext xprt_etScaleFactor text:"1.0" fieldWidth:32 align:#right
			checkbox xprt_SmoothingGroups "SmoothingGroups" checked:false
			checkbox xprt_BakeAnimation "BakeAnimation" checked:true
			checkbox xprt_NormalsPerPoly "NormalsPerPoly" checked:false
			checkbox xprt_Skin "Skin" checked:true
			label xprt_UpAxis "UpAxis" across:2
			dropdownlist xprt_ddlUpAxis items:#("Z", "Y") selection:2
		)
		button xprt_export "Export" width:120

		on xprt_export pressed do (
			TC.export_fbx()
		)
	)
	
-- ==================================
--					FBX Export Settings
-- ==================================
	rollout ins_dialog "Insert Frames" (
		label ins_NumFrames "Frames" across:2
		edittext ins_etNumFrames text:"0" fieldWidth:32 align:#right
		button ins_Insert "Insert" width:120
		
		on ins_Insert pressed do (
			TC.insert_frames()
			try(destroyDialog TC.ins_dialog)catch()
		)
	)


-- ==================================
--					NAME_ROL
-- ==================================
	rollout name_rol "Range Name" (
		fn proceed arg =	(
			if arg != "" do	TC.uniqueName arg 1
			try(destroyDialog TC.name_rol)catch()
		)
		edittext edt_name "" fieldWidth:120 across:2 offset:[-10,2]
		button bt_ok "Ok" width:30 height:20 offset:[30,1]
		on edt_name entered arg do proceed arg
		on bt_ok pressed do proceed arg
	)


-- ==================================
--					NEW_NAME_ROLL
-- ==================================
	rollout new_name_rol ( "Rename " + (filterString TC.ddl_range2.SelectedItem " " )[1]) ( --"New Range Name"
		fn proceed arg =	(
			if arg != "" do	TC.uniqueName arg 2
			try(destroyDialog TC.new_name_rol)catch()
		)
		edittext edt_new_name "" fieldWidth:120 across:2 offset:[-10,2]
		button bt_new_ok "Ok" width:30 height:20 offset:[30,1]
		on edt_new_name entered arg do proceed arg
		on bt_new_ok pressed do	proceed arg
	)


-- ==================================
--					TIMERANGE
-- ==================================

rollout timerange ("TimeLine Control v." + TC.ver as string)
(
	button bt_addrange "+"  height:20 tooltip:"Add Current Range To List" pos:[0,0] --width:30 across:14
	dotnetcontrol ddl_range2  "combobox" pos:[23,0] height:55 width:200
	spinner sp_move "" range:[-1,1,1] tooltip:"change range position in list" type:#integer fieldWidth:0 pos:[223,2] --pos:[223,2]
	button bt_rename "Rename" height:20 tooltip:"Rename" pos:[235,0]
	button bt_sortName "srtN" height:20 tooltip:"Sort by Names" pos:[290,0]
	button bt_sortFrame "srtF" height:20 tooltip:"Sort by Frames" pos:[326,0]
	button bt_delete "-" width:30 height:20 tooltip:"Delete Current Range From List" pos:[361,0]
	spinner sp_start "From" range:[-99999999,99999999,0] type:#integer fieldWidth:50 pos:[397,2]
	spinner sp_end "To" range:[-99999999,99999999,100] type:#integer fieldWidth:50 pos:[488,2]
	button bt_Prevframe "<<" width:20 height:20 tooltip:"Previous Key" pos:[564,0]
	button bt_Nextframe ">>" width:20 height:20 tooltip:"Next Key" pos:[584,0]

	--label ttttest "5" width:26 height:20 pos:[750,2]
	
	label l_playSpeed "1x"  width:26 height:20 pos:[874,2] align:#right --style_sunkenedge:true
	spinner sp_playSpeed range:[1,5,3] tooltip:"chant" type:#integer fieldWidth:0 pos:[900,2] align:#right
	checkbox cb_loop "Loop" checked:true tooltip:"Playback Loop" pos:[820,2]
	button bt_expSettings "FBX" height:20 tooltip:"Open FBX Export Settings" pos:[914,0] --enabled:false
	button bt_insFrames "Ins" height:20 tooltip:"Insert new empty frames to the selected bones at the end of the current timeline" pos:[948,0] --enabled:false
	button bt_TCsettings "..." width:31 height:20 tooltip:"Open TimeLine Control Settings" pos:[982,0]
	button bt_close "X" height:20 tooltip:"Close" pos:[1013,0]
--  =====================================================================

	on timerange open do (
		-- fix for 201x versions... 1st one
		if (GetDirectories (getDir #plugcfg + "\\tc")).count == 0 do (
			makeDir (getDir #plugcfg + "\\tc")
		)
		TC.ddl_range2 = timerange.ddl_range2
		TC.sp_start = timerange.sp_start
		TC.sp_end = timerange.sp_end
		TC.sp_move = timerange.sp_move
		TC.fileOpen()
		TC.Autocomplete = (execute (TC.readINI "Data" "Autocomplete"))
		TC.settings = fbx_settings
		TC.insertSettings = ins_dialog
		timeConfiguration.playbackLoop = timerange.cb_loop.checked
		
	)


	on bt_addrange pressed do (
		try(createdialog name_rol)catch()
		TC.name_rol = name_rol
		setFocus name_rol.edt_name
	)

--	autocomplete
--if classof TC.Autocomplete == BooleanClass
	on ddl_range2 TextUpdate senderArg arg do (
		if  TC.ddl_range2.Text != "" and (classof TC.Autocomplete==BooleanClass) and TC.hitTest and TC.Autocomplete then (
			index = TC.ddl_range2.FindString (filterString TC.ddl_range2.Text " ")[1]
			tempName = (filterString TC.ddl_range2.Text " ")[1] --TC.ddl_range2.Text
			TC.ddl_range2.SelectedIndex = index
			Anim_Range = (TC.sp_start.value as string + " " + TC.sp_end.value as string)
			newName =  ( tempName + "   : " + Anim_Range )
			TC.ddl_range2.Text = newName
			TC.ddl_range2.Select tempName.count 0
		) else (
			lastSelection = (execute (TC.readINI "Data" "LastSelection"))
			if classof lastSelection == Integer do (
				TC.ddl_range2.SelectedIndex = lastSelection
				TC.ddl_range2.Text = TC.ddl_range2.items.item[lastSelection]
			)
			TC.ddl_range2.Select 0 0
		)
	)

--	combobox selection change
	on ddl_range2 SelectedIndexChanged senderArg arg do (
		TC.load_Range2(TC.ddl_range2.SelectedItem)
		TC.updateSp_Move()
		index = TC.ddl_range2.SelectedIndex
		if index != -1 do (
			TC.writeINI "Data" "LastSelection" (index as string)
		)
	)

	on ddl_range2 MouseClick senderArg arg do (
		if classof TC.Autocomplete == BooleanClass and TC.Autocomplete then (
		--if classof TC.Autocomplete == BooleanClass then (
			--if TC.Autocomplete do TC.ddl_range2.SelectALL()
		) else (
				TC.ddl_range2.DroppedDown = true
				TC.ddl_range2.Select 0 0
		)
	)
	on ddl_range2 MouseEnter senderArg arg do TC.hitTest = true
	on ddl_range2 MouseLeave senderArg arg do (
		TC.hitTest = false
		LastSelection = (execute (TC.readINI "Data" "LastSelection"))
		if classof LastSelection == Integer and TC.ddl_range2.items.count > 0 do TC.ddl_range2.SelectedIndex = LastSelection
	)
	
	on sp_move changed val do TC.moveListItem (sp_move.value)

	on bt_rename pressed do	(
		try(createdialog new_name_rol)catch()
		setFocus new_name_rol.edt_new_name
		TC.new_name_rol = new_name_rol
	)
	
	on bt_sortName pressed do TC.sortRanges false

	on bt_sortFrame pressed do TC.sortRanges true

	on bt_delete pressed do TC.deleteRange()

	on sp_end changed val do (
			if sp_end.value <= sp_start.value then sp_start.value = (sp_end.value)-1
			TC.setTimeRange()
	)
	
	on bt_Prevframe pressed do TC.goToPrev_Key()
	on bt_Nextframe pressed do TC.goToNext_Key()

	on sp_start changed val do (
			if sp_start.value >= sp_end.value then sp_end.value = (sp_start.value)+1
			TC.setTimeRange()
	)
	on sp_end changed val do (
			if sp_end.value <= sp_start.value then sp_start.value = (sp_end.value)-1
			TC.setTimeRange()
	)

	on sp_playSpeed changed val do (
		case of	(
			(val == 1):	(l_playSpeed.text="1/4x"; timeConfiguration.playbackSpeed = 1)
			(val == 2):	(l_playSpeed.text="1/2x"; timeConfiguration.playbackSpeed = 2)
			(val == 3):	(l_playSpeed.text="  1x"; timeConfiguration.playbackSpeed = 3)
			(val == 4):	(l_playSpeed.text="  2x"; timeConfiguration.playbackSpeed = 4)
			(val == 5):	(l_playSpeed.text="  4x"; timeConfiguration.playbackSpeed = 5)
		)
	)
	
	on bt_expSettings pressed do try(createdialog fbx_settings)catch()
	
	on bt_insFrames pressed do try(createdialog ins_dialog)catch() 
	
	on cb_loop changed val do timeConfiguration.playbackLoop = val
	
	on bt_TCsettings pressed do try(createdialog tc_settings)catch()
	
	on bt_close pressed do	(
		try(cui.UnRegisterDialogBar timerange)catch()
		try(destroyDialog timerange)catch()
	)
)

TC = TCstructDef()

-- ==================================
--			CREATE ROLLOUT
-- ==================================
createdialog timerange 1036 20 style:#(#style_titlebar, #style_border, #style_sysmenu, #style_minimizebox)
cui.RegisterDialogBar timerange style:#(#cui_dock_bottom,#cui_dock_top, #cui_floatable, #style_toolwindow)
cui.DockDialogBar timerange #cui_dock_bottom
callbacks.addScript #animationRangeChange "TC.updateSp_Values()" id:#Sp_Values
callbacks.addScript #filePostOpen "TC.fileOpen()" id:#Sp_Values
callbacks.addScript #systemPostNew "TC.fileOpen()" id:#Sp_Values
callbacks.addScript #filePostSave "TC.fileSave()" id:#Sp_Values
)