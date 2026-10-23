The iPhone and the stage disagree by one fixed rotation. ARKit’s pose is right-handed and metric, but its horizontal axes are rolled −90° about the screen axis relative to the stage. The stage removes ARKit’s arbitrary opening orientation, then applies that roll. Translation and rotation use the same matrix.



Quaternions are \\((w, x, y, z)\\). A quaternion \\(q\\) rotates a vector by \\(q\\,v\\,q^\\ast\\). Multiplication \\(a \\otimes b\\) applies \\(b\\) first.



\*\*What the phone sends.\*\* Each frame is the ARKit camera transform. \\(q\\) is that rotation. \\(p\\) is the camera position in meters, already minus the first tracked position, so the phone’s own origin is where tracking locked. Gravity is up inside ARKit. The yaw of that world is whatever the phone was doing when the session started, so the absolute pose is not yet the stage’s pose.



\*\*Stage axes.\*\* \\(+X\\) is right, \\(+Y\\) is up, \\(+Z\\) is toward you. The identity orientation is the phone upright with the screen toward you.



\*\*Opening lock.\*\* The first 10 poses are averaged. Components are flipped into the same hemisphere before the sum, then normalized to \\(\\bar q\\). The positions average to \\(\\bar o\\). That hold is defined to be the identity, at the origin. Alone, this would copy ARKit’s local axes onto the stage axes. Those axes were wrong, so a constant fix is baked into the same lock.



\*\*The measured error.\*\* The first comparison showed turns and slides on \\(X\\) landing on \\(Z\\). A \\(+90^\\circ\\) yaw was applied as a trial:



\\\[

R\_y(+90^\\circ) = \\begin{bmatrix} 0 \& 0 \& 1 \\\\ 0 \& 1 \& 0 \\\\ -1 \& 0 \& 0 \\end{bmatrix}

\\]



so an ARKit vector \\((x, y, z)\\) was drawn as \\((z, y, -x)\\). On that build the remaining mismatch was one cycle, for both movement and rotation:



\\\[

+X \\to +Y,\\quad +Y \\to +Z,\\quad +Z \\to +X

\\]



In matrix form, with columns as the images of the basis vectors:



\\\[

\\sigma = \\begin{bmatrix} 0 \& 0 \& 1 \\\\ 1 \& 0 \& 0 \\\\ 0 \& 1 \& 0 \\end{bmatrix}

\\]



That is \\(+120^\\circ\\) about the diagonal \\((1,1,1)\\). Its quaternion is \\(\\left(\\tfrac12,\\tfrac12,\\tfrac12,\\tfrac12\\right)\\). The inverse is \\(-120^\\circ\\) about the same axis:



\\\[

\\sigma^{-1} = \\left(\\tfrac12,-\\tfrac12,-\\tfrac12,-\\tfrac12\\right)

\\]



\*\*The net fix.\*\* \\(\\sigma^{-1}\\) composed with the trial yaw collapses to a single roll. Multiplying those two quaternions gives



\\\[

R\_\\mathrm{fix} = \\sigma^{-1} \\otimes R\_y(+90^\\circ) = \\left(\\tfrac{\\sqrt2}{2},\\, 0,\\, 0,\\, -\\tfrac{\\sqrt2}{2}\\right) = R\_z(-90^\\circ)

\\]



\\\[

R\_z(-90^\\circ) = \\begin{bmatrix} 0 \& 1 \& 0 \\\\ -1 \& 0 \& 0 \\\\ 0 \& 0 \& 1 \\end{bmatrix}

\\]



An ARKit vector \\((x, y, z)\\), expressed in the opening camera frame, is drawn as



\\\[

(x, y, z) \\mapsto (y,\\, -x,\\, z)

\\]



\\(Z\\), the screen axis, stays put. \\(X\\) and \\(Y\\) swap with a sign, which is a \\(90^\\circ\\) roll in the plane of the screen. That matches a portrait hold against ARKit’s camera basis: the camera axes are fixed to the sensor, and a roll about \\(Z\\) is what lines them up with “right” and “up” on the stage.



\*\*How a later sample is drawn.\*\* With offset \\(o = R\_\\mathrm{fix} \\otimes \\bar q^\\ast\\),



\\\[

\\begin{aligned}

q\_\\mathrm{stage} \&= o \\otimes q \\otimes R\_\\mathrm{fix}^\\ast \\\\

p\_\\mathrm{stage} \&= R(o)\\,(p - \\bar o)

\\end{aligned}

\\]



At the opening average, \\(q = \\bar q\\) and \\(p = \\bar o\\), so \\(q\_\\mathrm{stage}\\) is the identity and \\(p\_\\mathrm{stage}\\) is the origin. The roll does not tilt the resting phone.



A small move in the opening camera frame, \\(v\\), arrives as the ARKit world displacement \\(p - \\bar o = R(\\bar q)\\,v\\). Substituting gives



\\\[

p\_\\mathrm{stage} = R\_\\mathrm{fix}\\, v = (v\_y,\\, -v\_x,\\, v\_z)

\\]



A local turn \\(\\delta\\), with \\(q = \\bar q \\otimes \\delta\\), becomes



\\\[

q\_\\mathrm{stage} = R\_\\mathrm{fix} \\otimes \\delta \\otimes R\_\\mathrm{fix}^\\ast

\\]



That is \\(\\delta\\) with its axis rotated by the same matrix. A slide along an axis and a turn about that axis stay tied together.

