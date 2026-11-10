-- GrandMA3 Patch2PDF - https://github.com/leonreucher/grandma3-patch2pdf
-- PDF writer based on https://github.com/catseye/pdf.lua

---------------------------------------------------------------------------
-- PDF creation part
---------------------------------------------------------------------------

local PDF = {}

-- Helvetica / Helvetica-Bold advance widths (1/1000 em) for codes 32..126 (WinAnsiEncoding)
local WIDTHS_REGULAR = {
	278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
	556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
	1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
	667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
	333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
	556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
}
local WIDTHS_BOLD = {
	278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
	556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
	975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
	667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
	333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
	611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
}
-- Latin-1 192..255 -> base letter used for the width estimate ("?" = default width)
local LATIN1_BASE = "AAAAAA?CEEEEIIIIDNOOOOO?OUUUUY??aaaaaa?ceeeeiiii?nooooo?ouuuuy?y"

-- Unicode code points outside Latin-1 that WinAnsiEncoding can show
local WINANSI_EXTRA = {
	[0x20AC] = 0x80, [0x201A] = 0x82, [0x0192] = 0x83, [0x201E] = 0x84, [0x2026] = 0x85,
	[0x2020] = 0x86, [0x2021] = 0x87, [0x02C6] = 0x88, [0x2030] = 0x89, [0x0160] = 0x8A,
	[0x2039] = 0x8B, [0x0152] = 0x8C, [0x017D] = 0x8E, [0x2018] = 0x91, [0x2019] = 0x92,
	[0x201C] = 0x93, [0x201D] = 0x94, [0x2022] = 0x95, [0x2013] = 0x96, [0x2014] = 0x97,
	[0x02DC] = 0x98, [0x2122] = 0x99, [0x0161] = 0x9A, [0x203A] = 0x9B, [0x0153] = 0x9C,
	[0x017E] = 0x9E, [0x0178] = 0x9F,
}

-- Convert a (UTF-8) string to WinAnsiEncoding bytes. Invalid UTF-8 bytes are taken as Latin-1.
function PDF.to_winansi(s)
	s = tostring(s or "")
	local out = {}
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		local cp, len
		if c < 0x80 then
			cp, len = c, 1
		elseif c >= 0xC2 and c <= 0xDF and i + 1 <= n then
			local c2 = s:byte(i + 1)
			if c2 >= 0x80 and c2 <= 0xBF then
				cp, len = (c - 0xC0) * 64 + (c2 - 0x80), 2
			end
		elseif c >= 0xE0 and c <= 0xEF and i + 2 <= n then
			local c2, c3 = s:byte(i + 1, i + 2)
			if c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then
				cp, len = (c - 0xE0) * 4096 + (c2 - 0x80) * 64 + (c3 - 0x80), 3
			end
		elseif c >= 0xF0 and c <= 0xF4 and i + 3 <= n then
			local c2, c3, c4 = s:byte(i + 1, i + 3)
			if c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF and c4 >= 0x80 and c4 <= 0xBF then
				cp, len = 0x10000, 4 -- not representable
			end
		end
		if not cp then cp, len = c, 1 end

		local b
		if cp < 32 then
			b = 32
		elseif cp < 127 then
			b = cp
		elseif cp >= 160 and cp <= 255 then
			b = cp
		else
			b = WINANSI_EXTRA[cp] or 63 -- "?"
		end
		out[#out + 1] = string.char(b)
		i = i + len
	end
	return table.concat(out)
end

-- Width of an already WinAnsi encoded string in points
function PDF.text_width(encoded, bold, size)
	local widths = bold and WIDTHS_BOLD or WIDTHS_REGULAR
	local total = 0
	for i = 1, #encoded do
		local c = encoded:byte(i)
		local wdt
		if c >= 32 and c <= 126 then
			wdt = widths[c - 31]
		elseif c >= 192 then
			local base = LATIN1_BASE:byte(c - 191)
			if base ~= 63 then wdt = widths[base - 31] end
		end
		total = total + (wdt or 556)
	end
	return total * size / 1000
end

-- Truncate an encoded string so it fits into maxWidth (adds "...")
function PDF.fit(encoded, bold, size, maxWidth)
	if not maxWidth or PDF.text_width(encoded, bold, size) <= maxWidth then
		return encoded
	end
	local dots = "..."
	local limit = maxWidth - PDF.text_width(dots, bold, size)
	local cut = #encoded
	while cut > 0 and PDF.text_width(encoded:sub(1, cut), bold, size) > limit do
		cut = cut - 1
	end
	return encoded:sub(1, cut) .. dots
end

local function pdf_escape(encoded)
	return (encoded:gsub("[\\()]", "\\%0"))
end

PDF.new = function(pageWidth, pageHeight)
	local pdf = {}       -- instance variable
	local page = {}      -- array of page descriptors
	local object = {}    -- array of object contents
	local xref_table_offset -- byte offset of xref table

	local catalog_obj    -- global catalog object
	local pages_obj      -- global pages object
	local procset_obj    -- global procset object

	pageWidth = pageWidth or 612
	pageHeight = pageHeight or 792

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
			fh:write("<<\n")
			for k, v in pairs(obj.contents) do
				fh:write(string.format("/%s ", k))
				write_object(fh, v)
			end
			fh:write(">>\n")
		elseif obj.datatype == "array" then
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
				for _, str in ipairs(obj.contents) do
					len = len + string.len(str) + 1
				end
			end

			fh:write(string.format("<< /Length %d >>\n", len))
			fh:write("stream\n")

			if type(obj.contents) == "string" then
				fh:write(obj.contents)
			else -- assume array
				for _, str in ipairs(obj.contents) do
					fh:write(str)
					fh:write("\n")
				end
			end

			fh:write("\nendstream\n")
		end
	end

	write_indirect_object = function(fh, obj)
		obj.offset = fh:seek()
		fh:write(string.format("%d %d obj\n", obj.number, 0))
		write_direct_object(fh, obj)
		fh:write("endobj\n")
	end

	local write_header = function(fh)
		-- the binary comment marks the file as binary (non-ASCII text bytes follow)
		fh:write("%PDF-1.4\n%\226\227\207\211\n")
	end

	local write_body = function(fh)
		for _, obj in ipairs(object) do
			write_indirect_object(fh, obj)
		end
	end

	local write_xref_table = function(fh)
		xref_table_offset = fh:seek()
		fh:write("xref\n")
		fh:write(string.format("0 %d\n", #object + 1))
		fh:write("0000000000 65535 f \n")
		for _, obj in ipairs(object) do
			fh:write(string.format("%010d %05d n \n", obj.offset, 0))
		end
	end

	local write_trailer = function(fh)
		fh:write("trailer\n")
		fh:write("<<\n")
		fh:write(string.format("/Size %d\n", #object + 1))
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
				Encoding = "/WinAnsiEncoding",
			}
		}
		return font_obj
	end

	pdf.new_page = function(pdf)
		local pg = {}  -- instance variable
		local contents = {} -- array of operation strings
		local used_font = {} -- fonts used on this page

		local use_font = function(font_obj)
			for i, f in ipairs(used_font) do
				if font_obj == f then
					return "/F" .. i
				end
			end
			table.insert(used_font, font_obj)
			return "/F" .. #used_font
		end

		-- Text functions.
		pg.begin_text = function(pg)
			table.insert(contents, "BT")
		end

		pg.end_text = function(pg)
			table.insert(contents, "ET")
		end

		pg.set_font = function(pg, font_obj, size)
			table.insert(contents, string.format("%s %f Tf", use_font(font_obj), size))
		end

		pg.set_text_pos = function(pg, x, y)
			table.insert(contents, string.format("%f %f Td", x, y))
		end

		-- show a UTF-8 string (converted to WinAnsi and escaped)
		pg.show = function(pg, str)
			pg:show_encoded(PDF.to_winansi(str))
		end

		-- show an already WinAnsi encoded string (only escaped)
		pg.show_encoded = function(pg, encoded)
			table.insert(contents, string.format("(%s) Tj", pdf_escape(encoded)))
		end

		-- Graphics - path drawing functions.
		pg.moveto = function(pg, x, y)
			table.insert(contents, string.format("%f %f m", x, y))
		end

		pg.lineto = function(pg, x, y)
			table.insert(contents, string.format("%f %f l", x, y))
		end

		pg.rectangle = function(pg, x, y, w, h)
			table.insert(contents, string.format("%f %f %f %f re", x, y, w, h))
		end

		-- Graphics - colours.
		pg.setgray = function(pg, which, gray)
			assert(which == "fill" or which == "stroke")
			assert(gray >= 0 and gray <= 1)
			table.insert(contents, string.format(which == "fill" and "%f g" or "%f G", gray))
		end

		pg.setrgbcolor = function(pg, which, r, g, b)
			assert(which == "fill" or which == "stroke")
			assert(r >= 0 and r <= 1)
			assert(g >= 0 and g <= 1)
			assert(b >= 0 and b <= 1)
			table.insert(contents, string.format(which == "fill" and "%f %f %f rg" or "%f %f %f RG", r, g, b))
		end

		-- Graphics - line options.
		pg.setlinewidth = function(pg, w)
			table.insert(contents, string.format("%f w", w))
		end

		-- Graphics - path-terminating functions.
		pg.stroke = function(pg)
			table.insert(contents, "S")
		end

		pg.fill = function(pg)
			table.insert(contents, "f")
		end

		-- Graphics - state save/restore.
		pg.save = function(pg)
			table.insert(contents, "q")
		end

		pg.restore = function(pg)
			table.insert(contents, "Q")
		end

		pg.add = function(pg)
			local contents_obj = add {
				datatype = "stream",
				contents = contents
			}

			local resources = {
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
				resources.contents.Font.contents["F" .. i] = get_ref(font_obj)
			end

			local this_obj = add {
				datatype = "dictionary",
				contents = {
					Type = "/Page",
					Parent = get_ref(pages_obj),
					Contents = get_ref(contents_obj),
					Resources = resources
				}
			}

			table.insert(pages_obj.contents.Kids.contents, get_ref(this_obj))
			pages_obj.contents.Count = pages_obj.contents.Count + 1
		end

		table.insert(page, pg)
		return pg
	end

	-- returns true or nil, error message
	pdf.write = function(pdf, file)
		local fh, err = io.open(file, "wb")
		if not fh then
			return nil, err
		end

		write_header(fh)
		write_body(fh)
		write_xref_table(fh)
		write_trailer(fh)

		fh:close()
		return true
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
			Count = 0,
			MediaBox = string.format("[0 0 %d %d]", pageWidth, pageHeight),
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

---------------------------------------------------------------------------
-- Patch2PDF main plugin part
---------------------------------------------------------------------------

local pluginName = "Patch2PDF"
local documentTitle = "GrandMA3 Patch Export"
local footerNotice = "GrandMA3 - Patch2PDF"

local PAPER = {
	{ name = "A4",     width = 595, height = 842 },
	{ name = "Letter", width = 612, height = 792 },
}

-- column x positions and maximum text widths (points)
local xPosType = 20
local xPosID = 80
local xPosFixtureType = 140
local xPosFixtureName = 370
local xPosPatch = 540

local maxWidthType = xPosID - xPosType - 5
local maxWidthID = xPosFixtureType - xPosID - 5
local maxWidthFixtureType = xPosFixtureName - xPosFixtureType - 8
local maxWidthFixtureName = xPosPatch - xPosFixtureName - 8

local textSize = 10
local headerSize = 22
local rowHeight = 30
local bottomMargin = 50

local HUGE = math.huge

local function cleanId(v)
	if v == nil then return nil end
	v = tostring(v)
	if v == "" or v == "None" then return nil end
	return v
end

local function isFixtureType(fixture, name)
	local ft = fixture.fixturetype
	return ft ~= nil and ft.name == name
end

-- Build a plain record from a fixture handle. The show is never written to.
local function buildRecord(fixture, order)
	local main = fixture.ismultipatch and fixture.multipatchmain or nil
	local src = main or fixture

	local patch = fixture.patch or ""
	local universe, address = tostring(patch):match("^(%d+)%.(%d+)")
	local stage = fixture.stage

	local rec = {
		order = order,
		idtype = fixture.idtype or "-",
		fid = cleanId(src.fid),
		cid = cleanId(fixture.cid),
		name = fixture.name or "",
		mainName = main and main.name or nil,
		isMultipatch = main ~= nil,
		typeName = src.fixturetype and src.fixturetype.name or nil,
		modeName = src.mode,
		patch = tostring(patch),
		universe = universe and tonumber(universe) or nil,
		address = address and tonumber(address) or nil,
		stage = stage,
		stageName = stage and stage.name or "-",
		stageIndex = stage and stage.index or HUGE,
	}
	rec.fidNum = rec.fid and tonumber(rec.fid) or HUGE
	rec.cidNum = rec.cid and tonumber(rec.cid) or HUGE
	return rec
end

-- lexicographic compare of key lists, always a valid strict weak ordering
local function lessKeys(ka, kb)
	for i = 1, #ka do
		if ka[i] ~= kb[i] then
			return ka[i] < kb[i]
		end
	end
	return false
end

local function sortKey(rec, sortType, groupType)
	local key = {}
	if groupType == 3 then
		key[#key + 1] = rec.stageIndex
	end
	if sortType == 2 then
		-- FID (multipatch uses the FID of its main fixture and follows it), then CID
		key[#key + 1] = rec.fidNum
		key[#key + 1] = rec.cidNum
		key[#key + 1] = rec.isMultipatch and 1 or 0
	elseif sortType == 3 then
		-- DMX: unpatched fixtures last
		key[#key + 1] = rec.universe or HUGE
		key[#key + 1] = rec.address or HUGE
	end
	key[#key + 1] = rec.order
	return key
end

local function sortRecords(records, sortType, groupType)
	for _, rec in ipairs(records) do
		rec.sortKey = sortKey(rec, sortType, groupType)
	end
	table.sort(records, function(a, b) return lessKeys(a.sortKey, b.sortKey) end)
end

local function csvField(value, sep)
	value = tostring(value == nil and "-" or value)
	if value:find('[' .. sep .. '"\r\n]') then
		value = '"' .. value:gsub('"', '""') .. '"'
	end
	return value
end

local function createCSV(records, storagePath, sep)
	local lines = {}
	local header = { "type", "fid", "cid", "isMultipatch", "stage", "universe", "address", "universeAddress",
		"fixtureName", "fixtureType", "fixtureMode", "multipatchMain" }
	lines[1] = table.concat(header, sep)

	for _, rec in ipairs(records) do
		local fields = {
			rec.idtype, rec.fid or "-", rec.cid or "-", rec.isMultipatch and "true" or "false", rec.stageName,
			rec.universe or "-", rec.address or "-", rec.patch ~= "" and rec.patch or "-",
			rec.name ~= "" and rec.name or "-", rec.typeName or "-", rec.modeName or "-", rec.mainName or "-",
		}
		for i = 1, #fields do
			fields[i] = csvField(fields[i], sep)
		end
		lines[#lines + 1] = table.concat(fields, sep)
	end

	local file, err = io.open(storagePath, "wb")
	if not file then
		return nil, err
	end
	-- UTF-8 BOM for the ";" variant, so Excel (DE) shows umlauts correctly
	if sep == ";" then
		file:write("\239\187\191")
	end
	file:write(table.concat(lines, "\n"), "\n")
	file:close()
	return true
end

local function sanitizeFileName(name, fallback)
	name = tostring(name or ""):gsub('[\\/:%*%?"<>|%c]', "_")
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	name = name:gsub("%.[Pp][Dd][Ff]$", ""):gsub("%.[Cc][Ss][Vv]$", "")
	if name == "" then
		return fallback
	end
	return name
end

local function joinPath(dir, file)
	dir = tostring(dir or ""):gsub("[\\/]+$", "")
	return dir .. "/" .. file
end

local function Main(displayHandle, argument)
	local display = displayHandle and displayHandle.index or nil

	local function message(title, text)
		MessageBox({
			title = title,
			message = text,
			display = display,
			commands = { { value = 1, name = "Ok" } },
		})
	end

	local datetime = os.date("Created at: %d.%m.%Y %H:%M")
	local fileNameSuggestion = os.date("patch_export_%Y-%m-%d_%H-%M")
	local softwareVersion = Version()

	-- Drives: all except old software versions; removable devices preferred
	local drives = Root().Temp.DriveCollect
	local driveValues = {}
	local drivePaths = {}
	local defaultDrive, firstDrive
	local driveCount = 0
	for i, drive in ipairs(drives:Children()) do
		if drive.drivetype ~= "OldVersion" then
			local label = tostring(drive.name):gsub("[\r\n]+", " ")
			if driveValues[label] then label = label .. " (" .. i .. ")" end
			driveValues[label] = i
			drivePaths[i] = drive.path
			driveCount = driveCount + 1
			firstDrive = firstDrive or i
			if drive.drivetype == "Removeable" and not defaultDrive then
				defaultDrive = i
			end
		end
	end
	defaultDrive = defaultDrive or firstDrive

	if driveCount == 0 then
		message(pluginName .. " - Error", "No storage device found.")
		ErrEcho(pluginName .. ": no storage device found")
		return
	end

	local paperValues = {}
	for i, paper in ipairs(PAPER) do paperValues[paper.name] = i end

	local selectors = {
		{ name = "Drive",              selectedValue = defaultDrive, values = driveValues,                                          type = 1 },
		{ name = "Format",             selectedValue = 1, values = { ["PDF"] = 1, ["CSV (,)"] = 2, ["CSV (;)"] = 3 },         type = 1 },
		{ name = "Paper",              selectedValue = 1, values = paperValues,                                               type = 1 },
		{ name = "Export Filter",      selectedValue = 1, values = { ["Complete"] = 1, ["Selection Only"] = 2 },              type = 1 },
		{ name = "Sort",               selectedValue = 1, values = { ["Patch Window Order"] = 1, ["FID"] = 2, ["DMX"] = 3 }, type = 0 },
		{ name = "Grouping",           selectedValue = 1, values = { ["None"] = 1, ["Universe"] = 2, ["Stage"] = 3 },        type = 0 },
		{ name = "Include Multipatch", selectedValue = 1, values = { ["Yes"] = 1, ["No"] = 2 },                              type = 0 },
		{ name = "Skip unpatched",     selectedValue = 1, values = { ["No"] = 1, ["Yes"] = 2 },                              type = 0 },
	}

	local settings = MessageBox({
		title = "Patch 2 PDF",
		message = "Please adjust these settings as needed.",
		display = display,
		inputs = {
			{ value = fileNameSuggestion, name = "File name" },
			{ value = CurrentUser().name, name = "Author" },
		},
		selectors = selectors,
		commands = { { value = 1, name = "Export" }, { value = 2, name = "Cancel" } },
	})

	-- Cancel, Escape or closing the pop-up
	if not settings or settings.result ~= 1 then
		Printf(pluginName .. " aborted by user.")
		return
	end

	local sel = settings.selectors or {}
	local driveIndex = sel["Drive"] or defaultDrive
	local fileFormat = sel["Format"] or 1
	local paper = PAPER[sel["Paper"] or 1] or PAPER[1]
	local exportType = sel["Export Filter"] or 1
	local sortType = sel["Sort"] or 1
	local groupType = sel["Grouping"] or 1
	local includeMultipatch = (sel["Include Multipatch"] or 1) == 1
	local skipUnpatched = (sel["Skip unpatched"] or 1) == 2

	local inputs = settings.inputs or {}
	local fileName = sanitizeFileName(inputs["File name"], fileNameSuggestion)
	local author = inputs["Author"] or ""
	local drivePath = drivePaths[driveIndex] or drivePaths[defaultDrive]

	-- If grouping by universe is selected, order the fixtures by DMX address
	if groupType == 2 then
		sortType = 3
	end

	-------------------------------------------------------------------------
	-- Collect fixtures
	-------------------------------------------------------------------------
	local records = {}
	local seen = {}

	local function collect(fixture)
		if fixture == nil then return end
		-- disassemble fixture groupings
		if isFixtureType(fixture, "Grouping") then
			for _, child in ipairs(fixture:Children()) do
				collect(child)
			end
			return
		end
		-- skip the universal fixture
		if isFixtureType(fixture, "Universal") then return end
		if fixture.ismultipatch and not includeMultipatch then return end
		if skipUnpatched and (fixture.patch == nil or fixture.patch == "") then return end

		local addr = fixture:Addr()
		if seen[addr] then return end
		seen[addr] = true
		records[#records + 1] = buildRecord(fixture, #records + 1)
	end

	if exportType == 1 then
		-- all fixtures of all stages
		for _, stage in ipairs(Patch().Stages:Children()) do
			for _, fixture in ipairs(stage.fixtures:Children()) do
				collect(fixture)
			end
		end
	else
		if SelectionCount() <= 0 then
			message(pluginName .. " - Error", "No fixtures selected - please select at least one fixture and start again.")
			ErrEcho(pluginName .. ": no fixtures selected to be exported")
			return
		end
		local subfixtureIndex = SelectionFirst()
		while subfixtureIndex do
			local handle = GetSubfixture(subfixtureIndex)
			-- a selected cell/subfixture belongs to its patched fixture (stop at fixture groupings)
			while handle do
				local parent = handle:Parent()
				if parent and parent:GetClass() == "Fixture" and not isFixtureType(parent, "Grouping") then
					handle = parent
				else
					break
				end
			end
			collect(handle)
			subfixtureIndex = SelectionNext(subfixtureIndex)
		end
	end

	sortRecords(records, sortType, groupType)

	local storagePath = joinPath(drivePath, fileName)

	-------------------------------------------------------------------------
	-- CSV
	-------------------------------------------------------------------------
	if fileFormat == 2 or fileFormat == 3 then
		storagePath = storagePath .. ".csv"
		local ok, err = createCSV(records, storagePath, fileFormat == 3 and ";" or ",")
		if not ok then
			message(pluginName .. " - Error", "Could not write " .. storagePath .. "\n" .. tostring(err))
			ErrEcho(pluginName .. ": could not write " .. storagePath .. ": " .. tostring(err))
			return
		end
		Printf(pluginName .. ": CSV with " .. #records .. " fixtures created at " .. storagePath)
		message(pluginName, "CSV with " .. #records .. " fixtures created:\n" .. storagePath)
		return
	end

	-------------------------------------------------------------------------
	-- PDF
	-------------------------------------------------------------------------
	storagePath = storagePath .. ".pdf"

	local W, H = paper.width, paper.height
	local xRight = W - 20

	local p = PDF.new(W, H)
	local helv = p:new_font { name = "Helvetica" }
	local bold = p:new_font { name = "Helvetica", weight = "-Bold" }

	local pages = {}
	local page

	local function text(pg, isBold, size, x, y, str, maxWidth)
		local encoded = PDF.fit(PDF.to_winansi(str), isBold, size, maxWidth)
		pg:begin_text()
		pg:set_font(isBold and bold or helv, size)
		pg:set_text_pos(x, y)
		pg:show_encoded(encoded)
		pg:end_text()
	end

	local function line(pg, y, gray)
		pg:setrgbcolor("stroke", gray, gray, gray)
		pg:moveto(20, y)
		pg:lineto(xRight, y)
		pg:stroke()
	end

	local function printTableHeader(pg, y)
		text(pg, true, textSize, xPosType, y, "Type")
		text(pg, true, textSize, xPosID, y, "FID/CID")
		text(pg, true, textSize, xPosFixtureType, y, "Fixture Type / Fixture Mode")
		text(pg, true, textSize, xPosFixtureName, y, "Fixture Name")
		text(pg, true, textSize, xPosPatch, y, "U.Addr")
		line(pg, y - 10, 0)
	end

	local function printGroupLabel(pg, y, label)
		if label then
			text(pg, true, 12, xPosType, y, label, xRight - xPosType)
		end
	end

	local currentY
	local currentLabel

	local function newPage(label)
		page = p:new_page()
		pages[#pages + 1] = page
		printGroupLabel(page, H - 22, label)
		printTableHeader(page, H - 42)
		currentY = H - 72
	end

	local function groupKeyAndLabel(rec)
		if groupType == 2 then
			if rec.universe then
				return "U" .. rec.universe, "Universe " .. rec.universe
			end
			return "U-", "Unpatched"
		elseif groupType == 3 then
			return rec.stage or "-", "Stage: " .. rec.stageName
		end
		return nil, nil
	end

	-- First page with document information
	page = p:new_page()
	pages[1] = page

	local sortNames = { "Patch Window Order", "FID", "DMX" }
	local groupNames = { "None", "Universe", "Stage" }

	text(page, true, headerSize, 20, H - 67, documentTitle)
	text(page, false, textSize, 20, H - 92, datetime)
	text(page, false, textSize, 20, H - 107, "Software version: " .. tostring(softwareVersion))
	text(page, false, textSize, 20, H - 122, "Showfile: " .. tostring(Root().manetsocket.showfile), xRight - 20)
	text(page, false, textSize, 20, H - 137, "Author: " .. tostring(author), xRight - 20)
	text(page, false, textSize, 20, H - 152, "Parameters: " .. tostring(GetUIChannelCount()))
	text(page, false, textSize, 300, H - 92, "Fixtures: " .. #records)
	text(page, false, textSize, 300, H - 107, "Export: " .. (exportType == 2 and "Selection only" or "Complete")
		.. (includeMultipatch and "" or ", without multipatch") .. (skipUnpatched and ", without unpatched" or ""))
	text(page, false, textSize, 300, H - 122, "Sort: " .. sortNames[sortType] .. "   Grouping: " .. groupNames[groupType])

	if #records > 0 and groupType ~= 1 then
		local key, label = groupKeyAndLabel(records[1])
		currentLabel = label
		printGroupLabel(page, H - 172, label)
	end
	printTableHeader(page, H - 192)
	currentY = H - 222

	local lastGroupKey
	if #records > 0 then
		lastGroupKey = groupKeyAndLabel(records[1])
	end

	local function printFixtureRow(rec)
		-- new page for every group
		if groupType ~= 1 then
			local key, label = groupKeyAndLabel(rec)
			if key ~= lastGroupKey then
				lastGroupKey = key
				currentLabel = label
				newPage(label)
			end
		end
		-- page break
		if currentY < bottomMargin then
			newPage(currentLabel and (currentLabel .. " (cont.)") or nil)
		end

		local y = currentY
		text(page, false, textSize, xPosType, y, rec.idtype, maxWidthType)
		text(page, false, textSize, xPosID, y + 9, rec.fid or "-", maxWidthID)
		text(page, false, textSize, xPosID, y - 5, rec.cid or "-", maxWidthID)
		text(page, true, textSize, xPosFixtureType, y + 9, rec.typeName or "-", maxWidthFixtureType)
		text(page, false, textSize, xPosFixtureType, y - 5, rec.typeName and rec.modeName or "-", maxWidthFixtureType)

		local name = rec.name
		if rec.isMultipatch then
			name = name .. " [" .. tostring(rec.mainName) .. "]"
		end
		text(page, false, textSize, xPosFixtureName, y, name ~= "" and name or "-", maxWidthFixtureName)
		text(page, false, textSize, xPosPatch, y, rec.patch ~= "" and rec.patch or "-", xRight - xPosPatch)

		line(page, y - 10, 0.8)
		currentY = currentY - rowHeight
	end

	for _, rec in ipairs(records) do
		printFixtureRow(rec)
	end

	-- pagination + footer
	local pageCount = #pages
	for k, v in ipairs(pages) do
		local label = "Page " .. k .. "/" .. pageCount
		text(v, false, textSize, xRight - PDF.text_width(label, false, textSize), 10, label)
		text(v, false, textSize, 20, 10, footerNotice)
		v:add()
	end

	local ok, err = p:write(storagePath)
	if not ok then
		message(pluginName .. " - Error", "Could not write " .. storagePath .. "\n" .. tostring(err))
		ErrEcho(pluginName .. ": could not write " .. storagePath .. ": " .. tostring(err))
		return
	end
	Printf(pluginName .. ": PDF with " .. #records .. " fixtures (" .. pageCount .. " pages) created at " .. storagePath)
	message(pluginName, "PDF with " .. #records .. " fixtures (" .. pageCount .. " pages) created:\n" .. storagePath)
end

return Main
