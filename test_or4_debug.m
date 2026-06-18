% test_or4_debug.m — 独立测试 or4_street_view 的渲染逻辑
% 运行此脚本即可在不启动完整 UI 的情况下调试街景渲染

mapImage = imread('MapForUI.jpg');
[mapH, mapW, ~] = size(mapImage);
scale = 1.7;

% 模拟相机参数（地图中心，朝北，俯视15度）
cam.realX = mapW / 2 * scale;   % 地图中心 X (米)
cam.realY = mapH / 2 * scale;   % 地图中心 Y (米)
cam.height = 10;
cam.yawDegree = 0;
cam.pitchDegree = 15;
cam.focalPixel = 280;
cam.viewDist = 260;
cam.maxDist = 680;

viewW = 520;
viewH = 360;

fprintf('地图尺寸: %d x %d\n', mapW, mapH);
fprintf('相机: X=%.0f Y=%.0f yaw=%.0f pitch=%.0f height=%.0f focal=%.0f\n', ...
    cam.realX, cam.realY, cam.yawDegree, cam.pitchDegree, cam.height, cam.focalPixel);

% 计算基向量
[rcw, tcw, rwc, twc] = getCameraTransforms(cam);
[right, up, forward] = getCameraBaseVectors(cam);
cameraCenter = [cam.realX, cam.realY, cam.height];

fprintf('forward = [%.4f, %.4f, %.4f]\n', forward(1), forward(2), forward(3));
fprintf('right   = [%.4f, %.4f, %.4f]\n', right(1), right(2), right(3));
fprintf('up      = [%.4f, %.4f, %.4f]\n', up(1), up(2), up(3));
fprintf('cameraCenter = [%.1f, %.1f, %.1f]\n', cameraCenter(1), cameraCenter(2), cameraCenter(3));

viewImage = uint8(zeros(viewH, viewW, 3));
skyColor = uint8([205 225 245]);
outsideColor = uint8([235 235 235]);
[imgH, imgW, ~] = size(mapImage);

skyCount = 0;
hitCount = 0;
outCount = 0;
% Sample a few key pixels and print debug info
samples = [
    1, 1;          % top-left
    1, round(viewW/2);  % top-center
    round(viewH/2), round(viewW/2); % center
    viewH, round(viewW/2); % bottom-center
    ];
maxPixelValue = 0;

for vRow = 1:viewH
    for vCol = 1:viewW
        xPlane = vCol - viewW / 2;
        yPlane = viewH / 2 - vRow;
        rayDir = cam.focalPixel * forward + xPlane * right + yPlane * up;

        if rayDir(3) >= -0.0001
            viewImage(vRow, vCol, :) = skyColor;
            skyCount = skyCount + 1;
        else
            tGround = -cameraCenter(3) / rayDir(3);
            groundPt = cameraCenter + tGround * rayDir;

            dx = groundPt(1) - cam.realX;
            dy = groundPt(2) - cam.realY;
            distOnGround = sqrt(dx*dx + dy*dy);

            mapCol = round(groundPt(1) / scale);
            mapRow = round(mapH - groundPt(2) / scale);

            if tGround > 0 && distOnGround <= cam.maxDist && ...
               mapRow >= 1 && mapRow <= imgH && mapCol >= 1 && mapCol <= imgW
                viewImage(vRow, vCol, :) = mapImage(mapRow, mapCol, :);
                hitCount = hitCount + 1;
                if max(double(mapImage(mapRow, mapCol, :))) > maxPixelValue
                    maxPixelValue = max(double(mapImage(mapRow, mapCol, :)));
                end
            else
                viewImage(vRow, vCol, :) = outsideColor;
                outCount = outCount + 1;
            end
        end

        % Debug for sample points
        for si = 1:size(samples, 1)
            if vRow == samples(si, 1) && vCol == samples(si, 2)
                if rayDir(3) >= -0.0001
                    fprintf('Pixel (%d,%d): xPlane=%.1f yPlane=%.1f rayDir=[%.1f,%.1f,%.1f] SKY\n', ...
                        vRow, vCol, xPlane, yPlane, rayDir(1), rayDir(2), rayDir(3));
                else
                    fprintf('Pixel (%d,%d): xPlane=%.1f yPlane=%.1f rayDir=[%.1f,%.1f,%.1f] tGround=%.1f groundPt=[%.1f,%.1f,%.1f] mapCol=%d mapRow=%d\n', ...
                        vRow, vCol, xPlane, yPlane, rayDir(1), rayDir(2), rayDir(3), ...
                        tGround, groundPt(1), groundPt(2), groundPt(3), mapCol, mapRow);
                end
            end
        end
    end
end

fprintf('\n统计: sky=%d hit=%d out=%d (总 %d)\n', skyCount, hitCount, outCount, viewW*viewH);
fprintf('最大像素值: %d\n', maxPixelValue);

% 显示结果
figure;
imshow(viewImage);
title(sprintf('sky=%d hit=%d out=%d', skyCount, hitCount, outCount));

% ---- 相机变换函数（从 or4_street_view.m 复制） ----
function [rcw, tcw, rwc, twc] = getCameraTransforms(cam)
    pitch = cam.pitchDegree * pi / 180;
    yaw   = cam.yawDegree   * pi / 180;

    R1 = [1, 0, 0;
          0, cos(pitch), -sin(pitch);
          0, sin(pitch),  cos(pitch)];

    R2 = [1, 0, 0;
          0, 0, -1;
          0, 1,  0];

    az = pi - yaw;
    R3 = [cos(az), -sin(az), 0;
          sin(az),  cos(az), 0;
          0,        0,       1];

    T4 = [cam.realX; cam.realY; cam.height];

    R = R3 * R2 * R1;
    rcw = R;
    tcw = T4;

    rwc = rcw';
    twc = -rwc * tcw;
end

function [right, up, forward] = getCameraBaseVectors(cam)
    [rcw, ~, ~, ~] = getCameraTransforms(cam);
    right   = rcw(:, 1)';
    up      = rcw(:, 2)';
    forward = rcw(:, 3)';
end
