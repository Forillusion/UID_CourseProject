function varargout = or3_auto_align(action, mainFig, varargin)
%OR3_AUTO_ALIGN  OR3 车辆加载时自动对齐方向 + 车头朝上显示模式
%
%  核心函数（由 main.m 内部调用）：
%    angle = or3_auto_align('findAngle', mainFig, col, row)
%        返回 (col,row) 处最近道路的方向角（度），用于自动对齐。
%
%        优先使用 OR1 骨架边（精确）；若骨架不可用，分析 basicRoadMask
%        中该点附近道路像素的主方向。
%
%    out = or3_auto_align('rotateAround', img, cx, cy, deg)
%        绕任意点 (cx,cy) 旋转图像 img（手搓反向映射），用于车头朝上模式。

    switch action
        case 'findAngle'
            varargout{1} = findNearestRoadAngle(mainFig, varargin{1}, varargin{2});
        case 'rotateAround'
            varargout{1} = rotateMapAroundPoint(mainFig, varargin{1}, varargin{2}, varargin{3});
    end
end


%% ====================================================================
%   findNearestRoadAngle
%   返回 (col, row) 处道路的走向角（度，Matlab atan2d 约定）
%% ====================================================================
function angle = findNearestRoadAngle(fig, col, row)
    S = getappdata(fig, 'S');
    angle = 0;  % 默认 0°（水平向右）

    % ---- 方法 1：使用 OR1 骨架边 ----
    hasSkeleton = ~isempty(S.sk.nodes) && size(S.sk.nodes,1) >= 2 ...
               && ~isempty(S.sk.edges) && size(S.sk.edges,1) >= 1;
    if hasSkeleton
        bestDist = inf;
        bestAngle = 0;
        P = [col, row];
        for i = 1:size(S.sk.edges, 1)
            ni = S.sk.edges(i, 1);
            nj = S.sk.edges(i, 2);
            A = S.sk.nodes(ni, :);
            B = S.sk.nodes(nj, :);
            d = ptToSeg(P, A, B);
            if d < bestDist
                bestDist = d;
                % 方向：沿边的方向角
                dx = B(1) - A(1);
                dy = B(2) - A(2);
                if dx == 0 && dy == 0
                    bestAngle = 0;
                else
                    bestAngle = atan2d(dy, dx);
                end
            end
        end
        angle = bestAngle;
        return;
    end

    % ---- 方法 2：分析 basicRoadMask 中该点附近的道路像素主方向 ----
    mask = S.basicRoadMask;
    if isempty(mask), return; end
    [mH, mW, mC] = size(mask);
    scanR = 15;   % 扫描半径（像素）
    pts = [];     % 收集的附近道路像素坐标
    for dr = -scanR:scanR
        for dc = -scanR:scanR
            rr = round(row) + dr;
            cc = round(col) + dc;
            if rr < 1 || rr > mH || cc < 1 || cc > mW, continue; end
            if mC == 3
                v = (double(mask(rr,cc,1)) + double(mask(rr,cc,2)) + double(mask(rr,cc,3))) / 3;
            else
                v = double(mask(rr,cc));
            end
            if v > 160   % 白色像素 = 道路
                pts(end+1, :) = [cc, rr];   %#ok<AGROW>
            end
        end
    end
    if size(pts, 1) < 5, return; end

    % 居中后做简化 PCA（协方差矩阵主方向）
    cx0 = mean(pts(:,1));
    cy0 = mean(pts(:,2));
    dx  = pts(:,1) - cx0;
    dy  = pts(:,2) - cy0;
    Cxx = mean(dx .* dx);
    Cxy = mean(dx .* dy);
    Cyy = mean(dy .* dy);

    % 协方差矩阵最大特征值对应的特征向量方向
    theta = 0.5 * atan2(2 * Cxy, Cxx - Cyy);   % 主方向角（弧度）
    angle = rad2deg(theta);
end


%% ====================================================================
%   rotateMapAroundPoint
%   绕任意点 (cx,cy) 旋转图像（手搓反向映射，最近邻采样）
%% ====================================================================
function out = rotateMapAroundPoint(img, cx, cy, deg)
    [H, W, ~] = size(img);
    th = deg2rad(deg);
    c  = cos(th);
    s  = sin(th);

    % 1. 计算旋转后画布尺寸（绕 (cx,cy) 旋转四个角点）
    corners    = [0.5 0.5; W + 0.5 0.5; W + 0.5 H + 0.5; 0.5 H + 0.5];
    % 先平移到以 (cx,cy) 为原点，旋转，再平移回来
    centered    = corners - [cx cy];           % Nx2，以 (cx,cy) 为原点
    rotCentered = centered * [c -s; s c]';     % 旋转（注意转置：等同于 centered * R(θ)）
    rotCorners  = rotCentered + [cx cy];
    newW = ceil(max(rotCorners(:,1)) - min(rotCorners(:,1)));
    newH = ceil(max(rotCorners(:,2)) - min(rotCorners(:,2)));
    out  = uint8(255 * ones(newH, newW, 3));

    % 2. 新画布原点在旋转后空间中的偏移量
    shiftCol = min(rotCorners(:,1));
    shiftRow = min(rotCorners(:,2));

    % 3. 向量化反向映射
    [rowGrid, colGrid] = ndgrid(1:newH, 1:newW);
    % 新画布像素 (cc,rr) 在旋转后空间中的坐标
    rotX = shiftCol + colGrid(:) - 1;
    rotY = shiftRow + rowGrid(:) - 1;
    % 相对旋转中心的偏移（旋转后空间）
    xRot = rotX - cx;
    yRot = rotY - cy;
    % 反旋转回到原图空间（绕旋转中心）
    xOld =  xRot*c + yRot*s + cx;     % xRot*c + yRot*s = R(-θ)*[xRot;yRot] 的 x 分量
    yOld = -xRot*s + yRot*c + cy;
    rOld = round(yOld);
    cOld = round(xOld);

    valid = rOld>=1 & rOld<=H & cOld>=1 & cOld<=W;
    idx   = find(valid);
    for ch = 1:3
        tmp  = out(:,:,ch);
        tmp2 = img(:,:,ch);
        tmp(idx) = tmp2(rOld(idx) + (cOld(idx)-1)*H);
        out(:,:,ch) = tmp;
    end
end


%% ====================================================================
%   辅助：点到线段距离
%% ====================================================================
function d = ptToSeg(P, A, B)
    AB = B - A;
    AP = P - A;
    ab2 = dot(AB, AB);
    if ab2 == 0
        d = norm(P - A);
        return;
    end
    t = max(0, min(1, dot(AP, AB) / ab2));
    d = norm(P - (A + t * AB));
end
