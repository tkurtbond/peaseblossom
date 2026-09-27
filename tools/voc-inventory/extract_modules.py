"""extract_modules.py VOC_SOURCE VOC_INSTALL: writes, as JSON on standard
output, what voc_sources.read_all finds in voc's source clone and install."""

import json
import sys

import voc_sources

json.dump(voc_sources.read_all(sys.argv[1], sys.argv[2]), sys.stdout, indent=1)
