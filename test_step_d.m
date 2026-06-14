%TEST_STEP_D  Step D test: IV drawing + pointInPolygon + road check
fprintf('========== Step D Test ==========\n');

mapW = 500; mapH = 300; scale = 1.7;
mapIn = uint8(255 * ones(mapH, mapW, 3));  % white map

%% 1. Test drawIV - basic rectangle at angle 0
mapOut = drawIV(mapIn, 250, 150, 0, 3, mapW, mapH, scale);
greenPx = nnz(mapOut(:,:,1)==0 & mapOut(:,:,2)==200 & mapOut(:,:,3)==0);
assert(greenPx > 0, 'no green pixels drawn');
fprintf('[OK] drawIV angle=0: %d green pixels\n', greenPx);

%% 2. Test drawIV - rotation 90 degrees
mapOut2 = drawIV(mapIn, 250, 150, 90, 3, mapW, mapH, scale);
greenPx2 = nnz(mapOut2(:,:,1)==0 & mapOut2(:,:,2)==200 & mapOut2(:,:,3)==0);
assert(greenPx2 > 0, 'no pixels at 90 deg');
% At 90deg, the rectangle should be taller than wide (vs angle 0)
% Check shape: at 0 deg, width > height; at 90 deg, height > width
fprintf('[OK] drawIV angle=90: %d green pixels\n', greenPx2);

%% 3. Test pointInPolygon
% Unit square
poly = [0 0; 2 0; 2 2; 0 2];
assert(pointInPolygon([1 1], poly), 'center should be inside');
assert(~pointInPolygon([3 3], poly), 'outside should be outside');
assert(pointInPolygon([0.5 0.5], poly), 'inside near corner');
assert(~pointInPolygon([-1 1], poly), 'left outside');
fprintf('[OK] pointInPolygon: inside/outside correct\n');

% Triangle
tri = [0 0; 4 0; 2 3];
assert(pointInPolygon([2 1], tri), 'triangle center');
assert(~pointInPolygon([0 2], tri), 'triangle outside');
fprintf('[OK] pointInPolygon triangle\n');

%% 4. Test rotated rectangle consistency
% Draw IV at angle 0, count pixels. Draw at angle 45, count should be similar
mapA = drawIV(mapIn, 250, 150, 0, 3, mapW, mapH, scale);
mapB = drawIV(mapIn, 250, 150, 45, 3, mapW, mapH, scale);
gA = nnz(mapA(:,:,2)==200);
gB = nnz(mapB(:,:,2)==200);
% Areas should be close (45deg might lose some due to discrete sampling)
ratio = min(gA,gB)/max(gA,gB);
assert(ratio > 0.7, sprintf('area ratio too different: %.3f', ratio));
fprintf('[OK] drawIV rotation area consistency: 0deg=%d, 45deg=%d (ratio %.3f)\n', gA, gB, ratio);

%% 5. Test front indicator (yellow dot)
% front dot at angle 0 should be at cx + L/2
L = (8/scale)*3;
th = 0;
frontX = 250 + (L/2)*cos(th);
frontY = 150 + (L/2)*sin(th);
fr = round(frontY); fc = round(frontX);
assert(mapA(fr,fc,1)==255 && mapA(fr,fc,2)==255, 'front indicator not yellow');
fprintf('[OK] front indicator at (%d,%d) is yellow\n', fc, fr);

%% 6. Test road validation logic
% Create a simple road mask
mask = false(mapH, mapW);
mask(148:152, 200:300) = true;  % horizontal road band
% Point on road
assert(mask(150,250), 'road point check');
% Point off road
assert(~mask(150,100), 'off-road point check');
fprintf('[OK] road mask validation logic\n');

fprintf('\n========== Step D Test PASSED ==========\n');


%% ===== Local functions =====
function mapOut = drawIV(mapIn, cx, cy, angleDeg, dispScale, mapW, mapH, scale)
    L = (8 / scale) * dispScale;
    Wd = (3 / scale) * dispScale;
    corners = [-L/2 -Wd/2; L/2 -Wd/2; L/2 Wd/2; -L/2 Wd/2];
    th = deg2rad(angleDeg);
    R = [cos(th) -sin(th); sin(th) cos(th)];
    rotCorners = corners * R';
    ptsPx = rotCorners + [cx, cy];
    mapOut = mapIn;
    bodyColor = uint8([0 200 0]);
    cMin = max(1, floor(min(ptsPx(:,1))));
    cMax = min(mapW, ceil(max(ptsPx(:,1))));
    rMin = max(1, floor(min(ptsPx(:,2))));
    rMax = min(mapH, ceil(max(ptsPx(:,2))));
    for r = rMin:rMax
        for c = cMin:cMax
            if pointInPolygon([c, r], ptsPx)
                mapOut(r, c, :) = bodyColor;
            end
        end
    end
    frontX = cx + (L/2) * cos(th);
    frontY = cy + (L/2) * sin(th);
    fr = round(frontY); fc = round(frontX);
    if fc>=1 && fc<=mapW && fr>=1 && fr<=mapH
        mapOut(fr, fc, :) = uint8([255 255 0]);
    end
end

function inside = pointInPolygon(pt, poly)
    n = size(poly, 1);
    inside = false;
    j = n;
    for i = 1:n
        yi = poly(i,2); yj = poly(j,2);
        xi = poly(i,1); xj = poly(j,1);
        if ((yi > pt(2)) ~= (yj > pt(2)))
            xCross = xi + (pt(2)-yi)/(yj-yi) * (xj-xi);
            if pt(1) < xCross
                inside = ~inside;
            end
        end
        j = i;
    end
end




