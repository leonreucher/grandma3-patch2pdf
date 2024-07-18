-- PDF creation part


PDF = {}
PDF.new = function()
	local pdf = {}		-- instance variable
	local page = {}		-- array of page descriptors
	local object = {}	-- array of object contents
	local xref_table_offset	-- byte offset of xref table

	local catalog_obj	-- global catalog object
	local pages_obj		-- global pages object
	local procset_obj	-- global procset object

	--
	-- Private functions.
	--

	local add = function(obj)
		table.insert(object, obj)
		obj.number = #object
		return obj
	end

	local get_ref = function(obj)
		return string.format("%d 0 R", obj.number)
	end

	local write_object
	local write_direct_object
	local write_indirect_object

	write_object = function(fh, obj)
		if type(obj) == "table" and obj.datatype == "stream" then
			write_indirect_object(fh, obj)
		else
			write_direct_object(fh, obj)
		end
	end

	write_direct_object = function(fh, obj)
		if type(obj) ~= "table" then
			fh:write(obj .. "\n")
		elseif obj.datatype == "dictionary" then
			local k, v

			fh:write("<<\n")
			for k, v in pairs(obj.contents) do
				fh:write(string.format("/%s ", k))
				write_object(fh, v)
			end
			fh:write(">>\n")
		elseif obj.datatype == "array" then
			local v

			fh:write("[\n")
			for _, v in ipairs(obj.contents) do
				write_object(fh, v)
			end
			fh:write("]\n")
		elseif obj.datatype == "stream" then
			local len = 0

			if type(obj.contents) == "string" then
				len = string.len(obj.contents)
			else -- assume array
				local i, str
				
				for i, str in ipairs(obj.contents) do
					len = len + string.len(str) + 1
				end
			end

			fh:write(string.format("<< /Length %d >>\n", len))
			fh:write("stream\n")

			if type(obj.contents) == "string" then
				fh:write(obj.contents)
			else -- assume array
				local i, str
				
				for i, str in ipairs(obj.contents) do
					fh:write(str)
					fh:write("\n")
				end
			end

			fh:write("endstream\n")
		end
	end

	write_indirect_object = function(fh, obj)
		obj.offset = fh:seek()
		fh:write(string.format("%d %d obj\n", obj.number, 0))
		write_direct_object(fh, obj)
		fh:write("endobj\n")
	end

	local write_header = function(fh)
		fh:write("%PDF-1.0\n")
	end

	local write_body = function(fh)
		local i, obj
		
		for i, obj in ipairs(object) do
			write_indirect_object(fh, obj)
		end
	end

	local write_xref_table = function(fh)
		local i, obj

		xref_table_offset = fh:seek()
		fh:write("xref\n")
		fh:write(string.format("%d %d\n", 1, #object))
		for i, obj in ipairs(object) do
			fh:write(
			    string.format("%010d %05d n \n", obj.offset, 0)
			)
		end
	end

	local write_trailer = function(fh)
		fh:write("trailer\n")
		fh:write("<<\n")
		fh:write(string.format("/Size %d\n", #object))
		fh:write("/Root " .. get_ref(catalog_obj) .. "\n")
		fh:write(">>\n")
		fh:write("startxref\n")
		fh:write(string.format("%d\n", xref_table_offset))
		fh:write("%%EOF\n")
	end

	--
	-- Instance methods.
	--

	pdf.new_font = function(pdf, tab)
		local subtype = tab.subtype or "Type1"
		local name = tab.name or "Helvetica"
		local weight = tab.weight or ""
		local font_obj = add {
			datatype = "dictionary",
			contents = {
				Type = "/Font",
				Subtype = "/" .. subtype,
				BaseFont = "/" .. name .. weight,
			}
		}
		return font_obj
	end


	pdf.new_page = function(pdf)
		local pg = {}		-- instance variable
		local contents = {}	-- array of operation strings
		local used_font = {}	-- fonts used on this page

		--
		-- Private functions.
		--

		local use_font = function(font_obj)
			local i, f
			
			for i, f in ipairs(used_font) do
				if font_obj == f then
					return "/F" .. i
				end
			end
			
			table.insert(used_font, font_obj)
			return "/F" .. #used_font
		end

		--
		-- Instance methods.
		--

		--
		-- Text functions.
		--

		pg.begin_text = function(pg)
			table.insert(contents, "BT")
		end

		pg.end_text = function(pg)
			table.insert(contents, "ET")
		end

		pg.set_font = function(pg, font_obj, size)
			table.insert(contents,
			    string.format("%s %f Tf",
			        use_font(font_obj), size)
			)
		end

		pg.set_text_pos = function(pg, x, y)
			table.insert(contents,
			    string.format("%f %f Td", x, y)
			)
		end

		pg.show = function(pg, str)
			table.insert(contents,
			    string.format("(%s) Tj", str)
			)
		end

		pg.set_char_spacing = function(pg, spc)
			table.insert(contents,
			    string.format("%f Tc", spc)
			)
		end

		--
		-- Graphics - path drawing functions.
		--

		pg.moveto = function(pg, x, y)
			table.insert(contents,
			    string.format("%f %f m", x, y)
			)
		end

		pg.lineto = function(pg, x, y)
			table.insert(contents,
			    string.format("%f %f l", x, y)
			)
		end

		pg.curveto = function(pg, x1, y1, x2, y2, x3, y3)
			local str

			if x3 and y3 then
				str = string.format("%f %f %f %f %f %f c",
				x1, y1, x2, y2, x3, y3)
			else
				str = string.format("%f %f %f %f v",
				x1, y1, x2, y2)
			end
			
			table.insert(contents, str)
		end

		pg.rectangle = function(pg, x, y, w, h)
			table.insert(contents,
			    string.format("%f %f %f %f re",
			    x, y, w, h)
			)
		end

		--
		-- Graphics - colours.
		--

		pg.setgray = function(pg, which, gray)
			assert(which == "fill" or which == "stroke")
			assert(gray >= 0 and gray <= 1)
			if which == "fill" then
				table.insert(contents,
				    string.format("%d g", gray)
				)
			else
				table.insert(contents,
				    string.format("%d G", gray)
				)
			end
		end

		pg.setrgbcolor = function(pg, which, r, g, b)
			assert(which == "fill" or which == "stroke")
			assert(r >= 0 and r <= 1)
			assert(g >= 0 and g <= 1)
			assert(b >= 0 and b <= 1)
			if which == "fill" then
				table.insert(contents,
				    string.format("%f %f %f rg", r, g, b)
				)
			else
				table.insert(contents,
				    string.format("%f %f %f RG", r, g, b)
				)
			end
		end

		pg.setcmykcolor = function(pg, which, c, m, y, k)
			assert(which == "fill" or which == "stroke")
			assert(c >= 0 and c <= 1)
			assert(m >= 0 and m <= 1)
			assert(y >= 0 and y <= 1)
			assert(k >= 0 and k <= 1)
			if which == "fill" then
				table.insert(contents,
				    string.format("%f %f %f %f k", c, m, y, k)
				)
			else
				table.insert(contents,
				    string.format("%f %f %f %f K", c, m, y, k)
				)
			end
		end

		--
		-- Graphics - line options.
		--

		pg.setflat = function(pg, i)
			assert(i >= 0 and i <= 100)
			table.insert(contents,
			    string.format("%d i", i)
			)
		end

		pg.setlinecap = function(pg, j)
			assert(j == 0 or j == 1 or j == 2)
			table.insert(contents,
			    string.format("%d J", j)
			)
		end

		pg.setlinejoin = function(pg, j)
			assert(j == 0 or j == 1 or j == 2)
			table.insert(contents,
			    string.format("%d j", j)
			)
		end

		pg.setlinewidth = function(pg, w)
			table.insert(contents,
			    string.format("%d w", w)
			)
		end

		pg.setmiterlimit = function(pg, m)
			assert(m >= 1)
			table.insert(contents,
			    string.format("%d M", m)
			)
		end

		pg.setdash = function(pg, array, phase)
			local str = ""
			local v
			
			for _, v in ipairs(array) do
				str = str .. v .. " "
			end

			table.insert(contents,
			    string.format("[%s] %d d", str, phase)
			)
		end

		--
		-- Graphics - path-terminating functions.
		--

		pg.stroke = function(pg)
			table.insert(contents, "S")
		end

		pg.closepath = function(pg)
			table.insert(contents, "h")
		end

		pg.fill = function(pg)
			table.insert(contents, "f")
		end

		pg.newpath = function(pg)
			table.insert(contents, "n")
		end

		pg.clip = function(pg) -- no effect until next newpath
			table.insert(contents, "W")
		end

		--
		-- Graphics - state save/restore.
		--

		pg.save = function(pg)
			table.insert(contents, "q")
		end

		pg.restore = function(pg)
			table.insert(contents, "Q")
		end

		--
		-- Graphics - CTM functions.
		--
		pg.transform = function(pg, a, b, c, d, e, f) -- aka concat
			table.insert(contents,
			    string.format("%f %f %f %f %f %f cm",
			        a, b, c, d, e, f)
			)		
		end

		pg.translate = function(pg, x, y)
			pg:transform(1, 0, 0, 1, x, y)
		end

		pg.scale = function(pg, x, y)
			if not y then y = x end
			pg:transform(x, 0, 0, y, 0, 0)
		end

		pg.rotate = function(pg, theta)
			local c, s = math.cos(theta), math.sin(theta)
			pg:transform(c, s, -1 * s, c, 0, 0)
		end

		pg.skew = function(pg, tha, thb)
			local tana, tanb = math.tan(tha), math.tan(thb)
			pg:transform(1, tana, tanb, 1, 0, 0)
		end

		pg.add = function(pg)
			local contents_obj, this_obj, resources
			local i, font_obj

			contents_obj = add {
				datatype = "stream",
				contents = contents
			}

			resources = {
				datatype = "dictionary",
				contents = {
					Font = {
						datatype = "dictionary",
						contents = {}
					},
					ProcSet = get_ref(procset_obj)
				}
			}

			for i, font_obj in ipairs(used_font) do
				resources.contents.Font.contents["F" .. i] =
				    get_ref(font_obj)
			end

			this_obj = add {
				datatype = "dictionary",
				contents = {
					Type = "/Page",
					Parent = get_ref(pages_obj),
					Contents = get_ref(contents_obj),
					Resources = resources
				}
			}
			
			table.insert(pages_obj.contents.Kids.contents,
			    get_ref(this_obj))
			pages_obj.contents.Count = pages_obj.contents.Count + 1
		end

		table.insert(page, pg)
		return pg
	end

	pdf.write = function(pdf, file)
		local fh

		if type(file) == "string" then
			fh = assert(io.open(file, "w"))
		else
			fh = file
		end

		write_header(fh)
		write_body(fh)
		write_xref_table(fh)
		write_trailer(fh)

		fh:close()
	end

	-- initialize... add a few objects that we know will exist.
	pages_obj = add {
		datatype = "dictionary",
		contents = {
			Type = "/Pages",
			Kids = {
				datatype = "array",
				contents = {}
			},
			Count = 0
		}
	}

	catalog_obj = add {
		datatype = "dictionary",
		contents = {
			Type = "/Catalog",
			Pages = get_ref(pages_obj)
		}
	}

	procset_obj = add {
		datatype = "array",
		contents = { "/PDF", "/Text" }
	}

	return pdf
end

-- Patch2PDF main plugin part

local documentTitle = "GrandMA3 Patch Export"
local footerNotice = "GrandMA3 - Patch2PDF"

local errMsgNoUSBDevice = "Please connect a removable storage device to the system."

local xPosType = 20
local xPosID = 80
local xPosFixtureType = 140
local xPosFixtureName = 370
local xPosPatch = 540

local yPosHeaderRow = 600
local yPosStageName = 770

local function Main(displayHandle,argument)
	local datetime = os.date("Created at: %d.%m.%Y %H:%M")
	local fileNameSuggestion = os.date("patch_export_%d-%m-%Y-%H-%M")
	local softwareVersion = Version()

    local selectors = {
		{ name="Skip unpatched", selectedValue=1, values={["No"]=1,["Yes"]=2}, type=0},
        { name="Drive", values={}, type=1},
		{ name="Export Filter", selectedValue=1, values={['Complete']=1,["Selection Only"]=2}, type=1},
		{ name="Sort", selectedValue=1, values={['Patch Window Order']=1,["FID"]=2, ["DMX"]=3}, type=0},
		{ name="Grouping", selectedValue=1, values={['None']=1,["Universe"]=2,["Stage"]=3}, type=0},
		{ name="Include Multipatch", selectedValue=1, values={["Yes"]=1,["No"]=2}, type=0},
    }

	-- Helper for assigning the drives in the list an ID
    local idCounter = 0

	-- Get currently connected storage devices
	local drives = Root().Temp.DriveCollect
	local usbConnected = false

    for _, drive in ipairs(drives) do
		idCounter = idCounter + 1
        if drive.drivetype ~= "OldVersion" and drive.drivetype == "Removeable" then 
			-- At least one removeable storage device was found
			usbConnected = true
            selectors[2].values[drive.name] = idCounter
            selectors[2].selectedValue = idCounter
        end
    end

	-- If no removeable storage device was found, the plugin will be aborted
    if usbConnected == false then
		local res =
        MessageBox(
			{
				title = "Patch2PDF - Error",
				message = "Please connect a removable storage device before running the plugin.",
				display = displayHandle.index,
				commands = {{value = 1, name = "Ok"}},
			}
    	)
        ErrEcho(errMsgNoUSBDevice)
        return
    end

   	local skipUnpatched = false

	local settings =
	MessageBox(
	{
		title = "Patch 2 PDF",
		message = "Please adjust these settings as needed.",
		display = displayHandle.index,
		inputs = {
			{value = fileNameSuggestion, name = "PDF title"}, 
			{value = CurrentUser().name, name = "Author"}}
	    ,
        selectors = selectors,
        commands = {{value = 1, name = "Export"}, {value = 2, name = "Cancel"}},
    }
    )

    local drivePath = ""
	local exportType = 1
	local sortType = 1
	local groupType = 1
	local includeMultipatch = 1

	if settings.result == 2 then
		Printf("Patch2PDF plugin aborted by user.")
		return
	end

    for k,v in pairs(settings.selectors) do
        if k == "Drive" then 
            drivePath = drives[v].path
        end
		if k == "Skip unpatched" then
			if v == 2 then
				skipUnpatched = true
			end
			if v == 1 then
				skipUnpatched = false
			end
		end
		if k == "Export Filter" then
			exportType = v
		end
		if k == "Sort" then
			sortType = v
		end
		if k == "Grouping" then
			groupType = v
		end
		if k == "Include Multipatch" then
			includeMultipatch = v
		end
    end

    local fileName = settings.inputs["PDF title"]
	local author = settings.inputs["Author"]

	-- Create a new PDF document
	local p = PDF.new()

	local helv = p:new_font{ name = "Helvetica"}
	local bold = p:new_font{ name = "Helvetica", weight = "-Bold"}

	-- Table for holding all pages which will be created during the printing process
	local pages = {}

	-- Create the initial page
	local page = p:new_page()
	table.insert(pages, page)

	page:save()


	local paramCount = GetUIChannelCount()
	
	local textSize = 10
	local headerSize = 22

	page:begin_text()
	page:set_font(bold, headerSize)
	page:set_text_pos(20, 725)
	page:show(documentTitle)
	page:end_text()

	page:begin_text()
	page:set_font(helv, textSize)
	page:set_text_pos(20, 700)
	page:show(datetime)
	page:end_text()

    page:begin_text()
	page:set_font(helv, textSize)
	page:set_text_pos(20, 685)
	page:show("Software version: " .. softwareVersion)
	page:end_text()

	page:begin_text()
	page:set_font(helv, textSize)
	page:set_text_pos(20, 670)
	page:show("Showfile: " .. Root().manetsocket.showfile)
	page:end_text()

	page:begin_text()
	page:set_font(helv, textSize)
	page:set_text_pos(20, 655)
	page:show("Author: " .. author)
	page:end_text()

	page:begin_text()
	page:set_font(helv, textSize)
	page:set_text_pos(20, 640)
	page:show("Parameters: " .. paramCount)
	page:end_text()

	page:restore()

	function printTableHeader(page, yPos)
		page:begin_text()
		page:set_font(bold, textSize)
		page:set_text_pos(xPosType, yPos)
		page:show("Type")
		page:end_text()

		page:begin_text()
		page:set_font(bold, textSize)
		page:set_text_pos(xPosID, yPos)
		page:show("FID/CID")
		page:end_text()

		page:begin_text()
		page:set_font(bold, textSize)
		page:set_text_pos(xPosFixtureType, yPos)
		page:show("Fixture Type / Fixture Mode")
		page:end_text()

		page:begin_text()
		page:set_font(bold, textSize)
		page:set_text_pos(xPosFixtureName, yPos)
		page:show("Fixture Name")
		page:end_text()

		page:begin_text()
		page:set_font(bold, textSize)
		page:set_text_pos(xPosPatch, yPos)
		page:show("U.Addr")
		page:end_text()

		page:setrgbcolor("stroke", 0, 0, 0)
		page:moveto(20, yPos-10)
		page:lineto(590, yPos-10)
		page:stroke()
	end

	printTableHeader(page, yPosHeaderRow)
	
	local currentY = 570
	local currentPage = page
	local pageCount = 1
	local nextLine = 30

	local lastUniverse = 0
	local lastStage = nil

	local maxFixtureTypeNameLength = 45
	local maxFixtureNameLength = 32
	local maxStageNameLength = 80

		function printStageName(page, yPos, stagename)
		page:begin_text()
		page:set_font(bold, textSize)
		page:set_text_pos(xPosType, yPos)
		page:show("Stage: ")
		page:set_font(helv, textSize);
		page:show(truncateString(stagename, maxStageNameLength))
		page:end_text()
	end

	function truncateString(str, max_length)
		if #str > max_length then
			truncatedString = str:sub(1, max_length) .. "..."
			return truncatedString
		else return str
		end
	end

	function printFixtureRow(page, fixture, posY)
		local fid = fixture.fid or "-"
		local cid = fixture.cid or "-"

		if fixture.ismultipatch then
			fid = fixture.multipatchmain.fid or "-"
		end

		if fid == "None" then fid = "-" end
		if cid == "None" then cid = "-" end
		

		-- GroupType 2 = Group by Universe
		if groupType == 2 then
			local universe, dmx = fixture.patch:match("(%d+)%.(%d+)")
			if universe ~= lastUniverse then
				lastUniverse = universe
				local newPage = p:new_page()
				pageCount = pageCount + 1
				table.insert(pages, newPage)
				currentPage = newPage
				printTableHeader(currentPage, 750)
				currentY = 720
				posY = currentY
				page = currentPage
			end
		end
		-- GroupType 3 = Group by Stage
		if groupType == 3 then
			if fixture.Stage ~= lastStage then
				lastStage = fixture.Stage
				local newPage = p:new_page()
				pageCount = pageCount + 1
				table.insert(pages, newPage)
				currentPage = newPage
				printTableHeader(currentPage, 750)
				printStageName(currentPage, yPosStageName, IntToHandle(lastStage).name)
				
				currentY = 720
				posY = currentY
				page = currentPage
			end
		end

		page:begin_text()
		page:set_font(helv, textSize)
		page:set_text_pos(xPosType, posY)
		page:show(fixture.idtype)
		page:end_text()

		page:begin_text()
		page:set_font(helv, textSize)
		page:set_text_pos(xPosID, posY+9)
		page:show(fid)
		page:end_text()

		page:begin_text()
		page:set_font(helv, textSize)
		page:set_text_pos(xPosID, posY-5)
		page:show(cid)
		page:end_text()

		page:begin_text()
		page:set_font(bold, textSize)
		page:set_text_pos(xPosFixtureType, posY+9)
		if fixture.ismultipatch == true then
			if fixture.multipatchmain.fixturetype ~= nil then
				page:show(truncateString(fixture.multipatchmain.fixturetype.name, maxFixtureTypeNameLength))
			else
				page:show("-")
			end
		else
			if fixture.fixturetype ~= nil then
				page:show(truncateString(fixture.fixturetype.name, maxFixtureTypeNameLength))
			else
				page:show("-")
			end
		end
		page:end_text()

		page:begin_text()
		page:set_font(helv, textSize)
		page:set_text_pos(xPosFixtureType, posY-5)
		if fixture.ismultipatch == true then
			if fixture.multipatchmain.fixturetype ~= nil and fixture.multipatchmain.mode ~= nil then
				page:show(truncateString(fixture.multipatchmain.mode, maxFixtureTypeNameLength))
			else
				page:show("-")
			end
		else
			if fixture.fixturetype ~= nil then
				if fixture.mode ~= nil then
					page:show(truncateString(fixture.mode, maxFixtureTypeNameLength))
				else 
					page:show("-")
				end
				
			else
				page:show("-")
			end
		end
		page:end_text()

		page:begin_text()
		page:set_font(helv, textSize)
		page:set_text_pos(xPosFixtureName, posY)
		-- If fixture is multi patch, check if it has a name, otherwise take the name of the parent fixture
		if fixture.ismultipatch == true then
			page:show(truncateString(fixture.name .. "[" .. fixture.multipatchmain.name .."]", maxFixtureNameLength))
		else
			page:show(truncateString(fixture.name, maxFixtureNameLength))
		end
		page:end_text()

		page:begin_text()
		page:set_font(helv, textSize)
		page:set_text_pos(xPosPatch, posY)
		page:show(fixture.patch)
		page:end_text()

		page:setrgbcolor("stroke", 0.8, 0.8, 0.8)
		page:moveto(20, posY-10)
		page:lineto(590, posY-10)
		page:stroke()

		currentY = currentY - nextLine

		if currentY < 50 then
			local newPage = p:new_page()
			pageCount = pageCount + 1
			table.insert(pages, newPage)
			currentPage = newPage
			printTableHeader(currentPage, 750)
			if groupType == 3 then
				printStageName(currentPage, yPosStageName, IntToHandle(lastStage).name)
			end
			currentY = 720
		end
	end

	local fixturesRaw = {}
	local cleanedFixtures = {}

	-- Helper function for removing unwanted objects and disassembling fixture groupings 
	function cleanupFixtures(fixture)
		if (fixture.fixturetype ~= nil) and (fixture.fixturetype.name == "Grouping") then
			local children = fixture:Children()
			for j = 1, #children do
				cleanupFixtures(children[j])
			end
			goto continue
		end
		-- Skip the fixture if its type is universal
		if (fixture.fixturetype ~= nil) and (fixture.fixturetype.name == "Universal") then
			goto continue
		end
		-- If fixture is a multipatch assign the dmx address of the parent fixture for correct sorting by DMX
		if fixture.ismultipatch then
			if includeMultipatch == 2 then
				goto continue
			end
			fixture.patch = fixture.multipatchmain.patch
		end
		-- Skip the fixture if not patched and skipUnpatched is enabled by the user
		if fixture.patch == "" and skipUnpatched then
			goto continue
		end
		table.insert(cleanedFixtures, fixture);
		::continue::
	end

	-- If grouping by universe is selected, order the fixtures by DMX address
	if groupType == 2 then
		sortType = 3
	end

	-- If grouping by stage is selected, order the fixtures by the default patch order
	if groupType == 3 then
		sortType = 1
		exportType = 1
	end

	-- Export all fixtures
	if exportType == 1 then
		-- Collect all fixtures from all stages
		for stageIndex, stage in ipairs(Patch().Stages) do
			for _, fixture in ipairs(stage.fixtures) do
				table.insert(fixturesRaw, fixture)
			end
		end
		
	end

	-- Export only selected fixtures
	if exportType == 2 then
		if SelectionCount() <= 0 then
			local res =
			MessageBox(
				{
					title = "Patch2PDF - Error",
					message = "No fixtures selected - please select at least one fixture and start again.",
					display = displayHandle.index,
					commands = {{value = 1, name = "Ok"}}
				}
			)
        	ErrEcho("No fixturesRaw selected to be exported")
			return
		end
		-- Collect all currently selected fixtures
		local subfixtureIndex = SelectionFirst();
		repeat
			local fixtureHandle = GetSubfixture(subfixtureIndex)
			table.insert(fixturesRaw, fixtureHandle)
			subfixtureIndex = SelectionNext(subfixtureIndex)
		until not subfixtureIndex;
	end

	for _, fixture in ipairs(fixturesRaw) do
		cleanupFixtures(fixture)
	end

	-- Sort by Fixture ID
	if sortType == 2 then
		table.sort(cleanedFixtures, function(a, b)
		local a_fid = a.fid and tonumber(a.fid) or math.huge  -- Assign -inf if fid is nil
		local b_fid = b.fid and tonumber(b.fid) or math.huge  -- Assign -inf if fid is nil
		if a.ismultipatch then
			a_fid = a.multipatchmain.fid and tonumber(a.multipatchmain.fid) or math.huge
		end
		if b.ismultipatch then
			b_fid = b.multipatchmain.fid and tonumber(b.multipatchmain.fid) or math.huge
		end

		if a.multipatchmain == b then
			return false
		end
		if b.multipatchmain == a then
			return true
		end
			
		return a_fid < b_fid
		end)
	end

	-- Sort by DMX address
	if sortType == 3 then
		table.sort(cleanedFixtures, function(a, b)
        local a_universe, a_dmx = a.patch:match("(%d+)%.(%d+)")
        local b_universe, b_dmx = b.patch:match("(%d+)%.(%d+)")
		
		if a.multipatchmain == b then
			return false
		end
		if b.multipatchmain == a then
			return true
		end

        if a_universe == nil and b_universe == nil then
            return false 
        elseif a_universe == nil then
            return false
        elseif b_universe == nil then
            return true
        end
        
        if a_universe ~= b_universe then
            return tonumber(a_universe) < tonumber(b_universe)
		-- dont reorder if a.patch == b.patch (multipatch fixture)
		elseif a_universe == b_universe and a_dmx == b_dmx then
			return false
        else
            return tonumber(a_dmx) < tonumber(b_dmx)
        end
    end)
	end

	if #cleanedFixtures > 0 then
		local universe, dmx = cleanedFixtures[1].patch:match("(%d+)%.(%d+)")
		lastUniverse = universe
		lastStage = cleanedFixtures[1].Stage
		if groupType == 3 then
			printStageName(page, yPosHeaderRow+20, IntToHandle(lastStage).name)
		end
	end
    for i = 1, #cleanedFixtures do
		printFixtureRow(currentPage, cleanedFixtures[i], currentY)
	end

	-- Iterate trough all created pages
	for k,v in pairs(pages) do
		-- Add pagination to the page
  		v:begin_text()
		v:set_font(helv, textSize)
		v:set_text_pos(520, 10)
		v:show("Page " ..k.. "/" ..pageCount)
		v:end_text()

		-- Add the footer notice to the page
		v:begin_text()
		v:set_font(helv, textSize)
		v:set_text_pos(20, 10)
		v:show(footerNotice)
		v:end_text()

		-- Add the page to the document
		v:add()
	end
	local storagePath = drivePath .. "/" .. fileName ..".pdf"
	p:write(storagePath)
	Printf("PDF created successfully at " .. storagePath)

	
end

return Main