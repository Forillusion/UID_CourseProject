%TEST_OR4_ROAD_POINT  Focused validation for OR4 road-point restriction.

mapImage = imread('MapForUI.jpg');
basicRoadMask = imread('RoadMask.jpg');
roadMask = [];
[mapH, mapW, ~] = size(mapImage);

[roadRow, roadCol] = findMaskPixel(basicRoadMask, true);
[offRow, offCol] = findMaskPixel(basicRoadMask, false);

assert(~isempty(roadRow) && ~isempty(roadCol), 'failed to find a road pixel');
assert(~isempty(offRow) && ~isempty(offCol), 'failed to find an off-road pixel');

assert(isRoadPointForUI(mapImage, basicRoadMask, roadMask, roadRow, roadCol), ...
    'road pixel should be accepted');
assert(~isRoadPointForUI(mapImage, basicRoadMask, roadMask, offRow, offCol), ...
    'off-road pixel should be rejected');

roadMask = false(mapH, mapW);
roadMask(offRow, offCol) = true;
assert(isRoadPointForUI(mapImage, basicRoadMask, roadMask, offRow, offCol), ...
    'explicit OR1 road mask should override off-road color');

fprintf('\n========== OR4 Road Point Test PASSED ==========\n');

function [row, col] = findMaskPixel(maskImage, wantRoad)
    row = [];
    col = [];
    grayMask = mean(double(maskImage), 3);
    if wantRoad
        idx = find(grayMask > 220, 1, 'first');
    else
        idx = find(grayMask < 40, 1, 'first');
    end
    if isempty(idx)
        return;
    end
    [row, col] = ind2sub(size(grayMask), idx);
end
