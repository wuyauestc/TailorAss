# Third-party notices

## Standard mannequin data (CC0)

`TrailorAss/Resources/GarmentCodeStandardBody.json` and its derived signed-distance
field originate from the MakeHuman hm08 base mesh, pinned to commit
`a8bc2d54ff0ac92e78ff71431b1023eda42bf482`, file
`makehuman/data/3dobjs/base.obj`. Its file header explicitly dedicates the asset
to CC0-1.0 (September 2020). Copyright holders at that release were Data
Collection AB, Joel Palmius, and Jonas Hauquier.

Source: https://github.com/makehumancommunity/makehuman/blob/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/makehuman/data/3dobjs/base.obj

Only body faces are retained; helper/joint geometry is removed. The mesh is
converted to metres, normalized to the named reference measurements, and fitted
within bounded scale ranges. The source SHA-256, derived file hashes and exact
transforms are recorded in `GarmentCodeStandardBodySource.json` and the build
script. The full CC0 notice is bundled as `MakeHuman-CC0-LICENSE.txt`.

The app uses this asset data; it does not embed the MakeHuman application.

## Pattern and numerical sources

The Swift L-BFGS-B compact-matrix and line-search ports reference SciPy 1.13.1
`scipy/optimize/lbfgsb_src/lbfgsb.f` (L-BFGS-B by C. Zhu, R. Byrd,
P. Lu-Chen and J. Nocedal, with J. L. Morales updates) and SciPy's DCSRCH.
SciPy's BSD license notice follows:

Copyright (c) 2001-2002 Enthought, Inc. 2003-2024, SciPy Developers.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above
   copyright notice, this list of conditions and the following
   disclaimer in the documentation and/or other materials provided
   with the distribution.
3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived
   from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The 21-point Gauss–Kronrod numerical coefficients and local error-estimate
formulas in `GarmentCodeQuadrature` follow QUADPACK DQK21 by Robert Piessens
and Elise de Doncker (coefficients evaluated by L. W. Fullerton):
https://netlib.org/quadpack/dqk21.f. The Swift integration implementation is
local code; it does not bundle or call a Fortran runtime.

The GarmentCode-compatible pattern data model and pattern-only geometry work in
`TrailorAss/Models/GarmentCodeGeometry.swift` are derived from the design and
serialization behavior of GarmentCode/PyGarment, pinned to commit
`d449629979028123a5c4dc9e732a2ec19b7fce31`.
The source-panel transform conventions in `GarmentCodePanelPlacement.swift`
and native lower-garment construction transforms in
`GarmentCodeLowerPlacement.swift`, `GarmentCodeUpperPlacement.swift` and
`GarmentCodeCompositionPlacement.swift` also reference that pinned code and
the following MIT notice.
`TrailorAss/Resources/GarmentCodeSiggraphShape.json` is a geometric
transformation of that commit's
`assets/img/siggraph_logo_thick_connection.svg`.

Copyright (c) 2024 Maria Korosteleva. Licensed under the MIT License:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.


## Native continuous collision detection

The local `NativeClothCollision` Swift package contains unmodified
Tight-Inclusion 1.0.4 at commit
`6f84001a790a9d3362b7c13d410037140d83fa2c` (MIT), the pinned Eigen 3.4.0
headers listed in its VendorManifest (MPL-2.0 and applicable permissive notices),
and spdlog 1.15.3 / fmt 11.2.0 (MIT). The build defines EIGEN_MPL2_ONLY and does
not enable GPL/LGPL Eigen modules.

Exact source repositories, commits, original paths and Git blob/SHA-256 values
are retained in `NativeClothCollision/VendorManifest.json`. Complete license
texts are retained in `NativeClothCollision/LICENSES/`. The App's About page
provides the applicable license texts and source links from its local bundle.
This package has no runtime Python, JIT, network or NVIDIA dependency. It does
not include the old NvidiaWarp-GarmentCode fork.


## IPC Toolkit body and cloth self-contact potentials (MIT)

The independent `NativeClothCollision/Sources/CIPCBodyContact` target vendors
original IPC Toolkit v1.6.1 leaf sources at commit
`19bcab7e1f5a0d2addfcd28513422ff248ea504e` and a local serial signed surface
builder/C ABI for fixed-body and all-moving cloth self-contact. The self builder
shares the same original leaf implementation and Eigen closure; its separate
local-source manifest is `IPCClothContactManifest.json`. The original 12 leaf
C++ files are unmodified. Source:
https://github.com/ipc-sim/ipc-toolkit/tree/19bcab7e1f5a0d2addfcd28513422ff248ea504e

`IPCBodyContactVendorManifest.json` retains the historical 335-file source,
header and license inventory with SHA-256 and Git blob SHA-1. That inventory
includes one locally authored body wrapper; its current owned-file exception
and the local body/self builder edge-order identity correction are explicitly
recorded in `IPCOrientationIdentityManifest.json`. All actual third-party
source and leaf files retain their original bytes. Its separate Eigen 3.4.0 header
closure is verified against release-archive SHA-256
`8586084f71f9bde545ee7fa6d00288b264a2b7ac3607b974e54d13e7162c1c72`,
with `EIGEN_MPL2_ONLY`. The existing Eigen MPL-2.0/BSD/Apache and spdlog/fmt MIT
notices above also apply; their full texts remain in the package and App
license resource. There is no TBB/libigl runtime dependency or non-commercial
Warp fork code in this target. The new IPC MIT notice follows.

MIT License

Copyright (c) 2020–2025 Zachary Ferguson

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
