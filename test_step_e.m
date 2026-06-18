%TEST_STEP_E  Step E test: rotateMap (hand-written inverse mapping)
fprintf('========== Step E Test ==========\n');

%% 1. Test rotateMap 0 degrees = identity
img = uint8(rand(50, 80, 3) * 255);
out0 = rotateMap(img, 0);
[H,W,~] = size(img);
% At 0 deg, new canvas should be same size (or +/-1 due to rounding)
[Ho,Wo,~] = size(out0);
fprintf('[1] 0deg: orig %dx%d -> rot %dx%d\n', H, W, Ho, Wo);
% Content should be nearly identical (may shift by 1px due to center rounding)
assert(abs(Ho-H)<=1 && abs(Wo-W)<=1, '0deg size changed too much');
fprintf('[OK] 0deg preserves size\n');

%% 2. Test rotateMap 90 degrees
out90 = rotateMap(img, 90);
[H90,W90,~] = size(out90);
fprintf('[2] 90deg: %dx%d -> %dx%d\n', H, W, H90, W90);
% At 90 deg, width and height should swap
assert(abs(H90-W)<=1 && abs(W90-H)<=1, '90deg dimensions should swap');
fprintf('[OK] 90deg swaps dimensions\n');

%% 3. Test rotateMap 180 degrees
out180 = rotateMap(img, 180);
[H180,W180,~] = size(out180);
fprintf('[3] 180deg: %dx%d -> %dx%d\n', H, W, H180, W180);
assert(abs(H180-H)<=1 && abs(W180-W)<=1, '180deg size should match');
fprintf('[OK] 180deg preserves size\n');

%% 4. Test content preservation - simple cross pattern
cross = uint8(zeros(100, 100, 3));
cross(:, 50, :) = 255;   % vertical white line
cross(50, :, :) = 255;   % horizontal white line
% Rotate 360 should return to original
out360 = rotateMap(cross, 360);
% Check center area still has white pixels
whiteCount = nnz(out360(:,:,1)==255 & out360(:,:,2)==255 & out360(:,:,3)==255);
whiteOrig = nnz(cross(:,:,1)==255);
fprintf('[4] cross pattern: orig=%d white, rot360=%d white\n', whiteOrig, whiteCount);
assert(whiteCount > 0, '360deg lost all content');
% 360 rotation should preserve content reasonably
ratio = whiteCount / whiteOrig;
fprintf('[OK] 360deg content ratio: %.3f\n', ratio);

%% 5. Test no holes (every pixel should have content in rotated region)
out45 = rotateMap(img, 45);
% Check that there are no all-zero rows in the middle region
[H45,W45,~] = size(out45);
midRows = out45(round(H45/2)-5:round(H45/2)+5, :, :);
nonZeroRows = any(midRows(:,:,1) > 0, 2);
assert(all(nonZeroRows), '45deg has zero rows in middle');
fprintf('[OK] 45deg no holes in middle\n');

%% 6. Test large image performance
big = uint8(rand(200, 300, 3) * 255);
tic;
outBig = rotateMap(big, 30);
t = toc;
fprintf('[6] 300x200 @30deg: %.2fs, output %dx%d\n', t, size(outBig,2), size(outBig,1));
assert(t < 5, 'rotation too slow');
fprintf('[OK] performance acceptable\n');

%% 7. Test with actual map
mapImg = imread('MapForUI.jpg');
tic;
outMap = rotateMap(mapImg, 45);
tMap = toc;
fprintf('[7] MapForUI @45deg: %.2fs, %dx%d -> %dx%d\n', tMap, ...
    size(mapImg,2), size(mapImg,1), size(outMap,2), size(outMap,1));
% Save for visual inspection
imwrite(outMap, 'test_rotation_output.png');
fprintf('[OK] map rotated, saved test_rotation_output.png\n');

fprintf('\n========== Step E Test PASSED ==========\n');


%% ===== Local function =====
function out = rotateMap(img, deg)
    [H, W, ~] = size(img);
    th = deg * pi / 180;
    c = cos(th); s = sin(th);
    corners = [0 0; W 0; W H; 0 H];
    rotCorners = corners * [c -s; s c]';
    newW = ceil(max(rotCorners(:,1)) - min(rotCorners(:,1)));
    newH = ceil(max(rotCorners(:,2)) - min(rotCorners(:,2)));
    out = uint8(zeros(newH, newW, 3));
    cxOld = W/2; cyOld = H/2;
    cxNew = newW/2; cyNew = newH/2;
    [rr, cc] = meshgrid(1:newW, 1:newH);
    x = cc(:) - cxNew;
    y = rr(:) - cyNew;
    xOld =  x*c + y*s + cxOld;
    yOld = -x*s + y*c + cyOld;
    rOld = round(yOld);
    cOld = round(xOld);
    valid = rOld>=1 & rOld<=H & cOld>=1 & cOld<=W;
    idx = find(valid);
    for ch = 1:3
        tmp = out(:,:,ch);
        tmp2 = img(:,:,ch);
        tmp(idx) = tmp2(rOld(idx) + (cOld(idx)-1)*H);
        out(:,:,ch) = tmp;
    end
end

