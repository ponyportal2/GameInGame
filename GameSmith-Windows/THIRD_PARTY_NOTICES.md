# Third-party notices

This distribution includes the Godot Engine binary supplied for the build.
Godot Engine is available under the MIT license.

Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Godot license information: https://godotengine.org/license/


## Fake AI API Simulator test source

`tools/fake-openai-endpoint/` contains the user-supplied snapshot of
`seyf1elislam/fake_openai_endpoint_ts` at commit
`d1105bf2573d95b043f5e1d0c5c427aa316d4487`, used only for local verification.
Its package metadata declares the project MIT-licensed. GameSmith's
`pi-server.mjs` is a small project-specific, zero-dependency scripted server
added beside that upstream source for deterministic real-Pi acceptance tests.


## Pi coding agent runtime

Production GameSmith integrates with a globally installed Pi coding agent rather
than shipping a separate homegrown provider/agent/compaction implementation.
The verification target is `@earendil-works/pi-coding-agent@1.4.0`, licensed MIT.
GameSmith supplies its own extension and host bridge, while Pi owns generic agent
history, streaming, retries, coding tools, provider calls, persistence, and compaction.

Source reference: https://github.com/earendil-works/pi

MIT License

Copyright (c) 2025 Mario Zechner

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## Included local voice runtime

The Windows x64 distribution includes **CPython 3.13.17** (official embeddable
package, unmodified), distributed under the Python Software Foundation License
Version 2 and its accompanying license history and bundled-component notices.
Copyright Python Software Foundation and the other copyright holders identified
in the upstream license. The complete license, including third-party notices for
included libraries, is retained in `tools/voice/licenses/PYTHON-LICENSE.txt` in the
source tree and `licenses/voice/PYTHON-LICENSE.txt` in the Windows distribution.
Source and release: https://www.python.org/downloads/release/python-31317/

The distribution also includes **pip 25.3** (unmodified wheel), under the MIT
license, Copyright The pip developers (see AUTHORS.txt in the wheel). pip vendors
additional libraries under their own licenses. All license and vendoring notice
files from the wheel are retained with their original paths under
`tools/voice/licenses/pip/` in the source tree and `licenses/voice/pip/` in the
Windows distribution. The wheel itself also retains its original notices.
Source: https://github.com/pypa/pip/tree/25.3

Exact artifact URLs and SHA-256 hashes are recorded in `tools/voice/bundled.json`
(and within GameSmith.pck). Recognition packages and model weights are downloaded
on demand rather than shipped; their licenses remain with those installed
packages. No model weights are included in this distribution.
