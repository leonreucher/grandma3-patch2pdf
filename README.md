# GrandMA3-Patch2PDF

## Overview ##

This open source projects allows users of the GrandMA3 software to export the fixture patch as an PDF file.

This plugin is pretty new and currently in beta testing - at this stage of development, errors can occur: please create an issue if you find anything which is not working as intended.

## Installation ##

Download the [latest release](https://github.com/leonreucher/grandma3-patch2pdf/releases/latest) and copy the two files from the archive to your GrandMA3 installation or onto an USB device. In GrandMA3 import the files from the plugins pool.

USB path for plugin files: 
/grandMA3/gma3_library/datapools/plugins

## Credits ##
The creation of the PDF document is based on the code from https://github.com/catseye/pdf.lua.

## Known limitations ##
Currently all stages in the patch are being exported - it is planned to add a filter option for selecting only the stages which should be exported. 

Only tested on GrandMA3 onPC version 2.0.2.0 on MacOS - I am not sure if the plugin is also working on consoles - please give a try and report :)

## Disclaimer ##

The project is delivered as is and there is no warranty that the plugin is working fine. This project is open source and has nothing to do with the MA Lighting GmbH coorperation. 
