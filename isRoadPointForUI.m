function isRoad = isRoadPointForUI(mapImage, basicRoadMask, roadMask, row, col)
%ISROADPOINTFORUI  Shared road-point validation for UI features.
%  Prefer explicit masks, then fall back to simple road-like color checks.

    [mapH, mapW, ~] = size(mapImage);
    rc = round(row);
    cc = round(col);
    if rc < 1 || rc > mapH || cc < 1 || cc > mapW
        isRoad = false;
        return;
    end

    if ~isempty(roadMask)
        isRoad = roadMask(rc, cc);
        return;
    end

    if ~isempty(basicRoadMask)
        isRoad = hasBasicMaskRoadNearby(basicRoadMask, rc, cc);
        return;
    end

    isRoad = hasRoadLikeColorNearby(mapImage, rc, cc);
end

function colorOk = hasRoadLikeColorNearby(mapImage, row, col)
    [mapH, mapW, ~] = size(mapImage);
    radius = 3;
    roadLikeCount = 0;
    totalCount = 0;

    for rr = row-radius:row+radius
        for cc = col-radius:col+radius
            if rr < 1 || rr > mapH || cc < 1 || cc > mapW
                continue;
            end
            totalCount = totalCount + 1;
            redValue = double(mapImage(rr, cc, 1));
            greenValue = double(mapImage(rr, cc, 2));
            blueValue = double(mapImage(rr, cc, 3));

            maxValue = max([redValue greenValue blueValue]);
            minValue = min([redValue greenValue blueValue]);
            averageValue = (redValue + greenValue + blueValue) / 3;

            greenDominance = greenValue - min(redValue, blueValue);
            blueDominance = blueValue - min(redValue, greenValue);

            isBright = averageValue > 135;
            isGrayLike = (maxValue - minValue) < 70;
            isNotGreenArea = greenDominance < 35;
            isNotWater = blueDominance < 45;

            if isBright && isGrayLike && isNotGreenArea && isNotWater
                roadLikeCount = roadLikeCount + 1;
            end
        end
    end

    colorOk = totalCount > 0 && roadLikeCount >= totalCount * 0.35;
end

function hasRoad = hasBasicMaskRoadNearby(maskImage, row, col)
    [maskH, maskW, ~] = size(maskImage);
    toleranceRadius = 14;
    hasRoad = false;

    for rr = row-toleranceRadius:row+toleranceRadius
        for cc = col-toleranceRadius:col+toleranceRadius
            if rr < 1 || rr > maskH || cc < 1 || cc > maskW
                continue;
            end
            if isMaskPixelWhite(maskImage, rr, cc)
                hasRoad = true;
                return;
            end
        end
    end
end

function isWhite = isMaskPixelWhite(maskImage, row, col)
    if size(maskImage, 3) == 3
        redValue = double(maskImage(row, col, 1));
        greenValue = double(maskImage(row, col, 2));
        blueValue = double(maskImage(row, col, 3));
        maskValue = (redValue + greenValue + blueValue) / 3;
    else
        maskValue = double(maskImage(row, col));
    end
    isWhite = maskValue > 160;
end
