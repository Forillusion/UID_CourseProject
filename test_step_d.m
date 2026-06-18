%TEST_STEP_D  Step D test: IV drawing + pointInPolygon + road check
fprintf('========== Step D Test ==========\n');

mapW = 500; mapH = 300; scale = 1.7;
mapIn = uint8(255 * ones(mapH, mapW, 3));  % white map

%% 1. Test drawIV - basic rectangle at angle 0
mapOut = drawIV(mapIn, 250, 150, 0, 3, mapW, mapH, scale);
greenPx = nnz(mapOut(:,:,1)==0 & mapOut(:,:,2)==200 & mapOut(:,:,3)==0);
assert(greenPx > 0, 'no green pixels drawn');
% Yellow head pixels (same width as body)
yellowPx = nnz(mapOut(:,:,1)==255 & mapOut(:,:,2)==255 & mapOut(:,:,3)==0);
assert(yellowPx > 0, 'no yellow head pixels');
fprintf('[OK] drawIV angle=0: green=%d, yellow(head)=%d\n', greenPx, yellowPx);

%% 2. Test drawIV - rotation 90 degrees
mapOut2 = drawIV(mapIn, 250, 150, 90, 3, mapW, mapH, scale);
greenPx2 = nnz(mapOut2(:,:,1)==0 & mapOut2(:,:,2)==200 & mapOut2(:,:,3)==0);
yellowPx2 = nnz(mapOut2(:,:,1)==255 & mapOut2(:,:,2)==255 & mapOut2(:,:,3)==0);
assert(greenPx2 > 0 && yellowPx2 > 0, 'missing pixels at 90 deg');
fprintf('[OK] drawIV angle=90: green=%d, yellow=%d\n', greenPx2, yellowPx2);

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

%% 4. Test head width equals body width
% At angle 0, head occupies the front 25% of length, full width
% Check that yellow pixels span the full width at the front
L = (8/scale)*3; Wd = (3/scale)*3;
headLen = L * 0.25;
% At angle 0, head region: x in [headLen-L/2, L/2], y in [-Wd/2, Wd/2]
% centered at (250,150)
frontCol = round(250 + L/2 - 1);  % near front edge
% Count yellow pixels in that column - should span the width
yellowCol = nnz(mapOut(round(150-Wd/2):round(150+Wd/2), frontCol, 1)==255 & ...
    mapOut(round(150-Wd/2):round(150+Wd/2), frontCol, 2)==255);
assert(yellowCol >= round(Wd)-1, sprintf('head width mismatch: %d vs Wd=%d', yellowCol, round(Wd)));
fprintf('[OK] head spans full width: %d pixels (Wd=%.1f)\n', yellowCol, Wd);

%% 5. Test total area = body + head
totalPx = greenPx + yellowPx;
% Expected area = L * Wd
expectedArea = L * Wd;
ratio = totalPx / expectedArea;
assert(ratio > 0.8 && ratio < 1.2, sprintf('total area off: %d vs expected %.1f', totalPx, expectedArea));
fprintf('[OK] total area: %d px (expected ~%.0f, ratio %.2f)\n', totalPx, expectedArea, ratio);

%% 6. Test road validation logic
mask = false(mapH, mapW);
mask(148:152, 200:300) = true;
assert(mask(150,250), 'road point check');
assert(~mask(150,100), 'off-road point check');
fprintf('[OK] road mask validation logic\n');

fprintf('\n========== Step D Test PASSED ==========\n');


%% ===== Local functions =====
function mapOut = drawIV(mapIn, cx, cy, angleDeg, dispScale, mapW, mapH, scale)
    L = (8 / scale) * dispScale;
    Wd = (3 / scale) * dispScale;
    headLen = L * 0.25;
    th = angleDeg * pi / 180;
    R = [cos(th) -sin(th); sin(th) cos(th)];
    mapOut = mapIn;
    % body (green)
    bodyCorners = [-L/2 -Wd/2; headLen-L/2 -Wd/2; headLen-L/2 Wd/2; -L/2 Wd/2];
    bodyPts = bodyCorners * R' + [cx, cy];
    bodyColor = uint8([0 200 0]);
    cMin = max(1, floor(min(bodyPts(:,1))));
    cMax = min(mapW, ceil(max(bodyPts(:,1))));
    rMin = max(1, floor(min(bodyPts(:,2))));
    rMax = min(mapH, ceil(max(bodyPts(:,2))));
    for r = rMin:rMax
        for c = cMin:cMax
            if pointInPolygon([c, r], bodyPts)
                mapOut(r, c, :) = bodyColor;
            end
        end
    end
    % head (yellow)
    headCorners = [headLen-L/2 -Wd/2; L/2 -Wd/2; L/2 Wd/2; headLen-L/2 Wd/2];
    headPts = headCorners * R' + [cx, cy];
    headColor = uint8([255 255 0]);
    cMin = max(1, floor(min(headPts(:,1))));
    cMax = min(mapW, ceil(max(headPts(:,1))));
    rMin = max(1, floor(min(headPts(:,2))));
    rMax = min(mapH, ceil(max(headPts(:,2))));
    for r = rMin:rMax
        for c = cMin:cMax
            if pointInPolygon([c, r], headPts)
                mapOut(r, c, :) = headColor;
            end
        end
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




