# GrandMA3-Patch2PDF

## Overview ##

This open source projects allows users of the GrandMA3 software (OnPC and Consoles) to export the fixture patch as an PDF file to an USB thumb drive.

Currently the following attributes are getting exported to the PDF file:
- Type (Fixture, Channel, Multipatch, Houselight, etc.)
- Fixture ID and Channel ID
- Fixture Type and Mode
- Fixture Name
- Universe and Address

You can sort the export by:
- Patch Window Order
- Fixture ID
- DMX Address

You can group the exported fixtures by:
- Universe
- Stage

Every group starts on a new page with a heading (e.g. "Universe 3", "Stage: FOH"). When grouping by universe, the fixtures are sorted by DMX address; when grouping by stage, the selected sorting is applied inside each stage.

You can select to either export the whole patch or just the currently selected fixtures (selected cells are mapped to their fixture).

Further options:
- Format: PDF, CSV (comma separated) or CSV (semicolon separated, UTF-8 with BOM - opens directly in Excel with German/European locale)
- Paper size: A4 or Letter
- Drive: any connected removable device or the internal drive
- Include multipatch fixtures (shown with their own DMX address) and skip unpatched fixtures

Names with special characters (umlauts, brackets, backslashes) are exported correctly, long names are shortened to fit their column.

This plugin is pretty new and currently in beta testing - at this stage of development, errors can occur: please create an issue if you find anything which is not working as intended.

## Installation ##

Download the [latest release](https://github.com/leonreucher/grandma3-patch2pdf/releases/latest) and copy the two files from the archive to your GrandMA3 installation or onto an USB device. In GrandMA3 import the files from the plugins pool.

USB path for plugin files: 
/grandMA3/gma3_library/datapools/plugins

## Credits ##
The creation of the PDF document is based on the code from https://github.com/catseye/pdf.lua.

## Known limitations ##
Currently all stages in the patch are being exported - it is planned to add a filter option for selecting only the stages which should be exported. 

## Disclaimer ##

The project is delivered as is and there is no warranty that the plugin is working fine. This project is open source and has nothing to do with the MA Lighting GmbH coorperation. 

![patch2pdf-config](https://github.com/leonreucher/grandma3-patch2pdf/assets/19686873/c622a612-5413-4b58-a439-c2756c1fdbb6)

![patch2pdf-screenshot](https://github.com/leonreucher/grandma3-patch2pdf/assets/19686873/eb05d2c0-685f-43af-93b7-957bf1082e3a)


