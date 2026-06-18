function varargout = or5_path_planning(action, mainFig, varargin)
%OR5_PATH_PLANNING  OR5 路径规划工具（弹出窗口，完全独立，基于 RoadMask.jpg）
%  用法：
%    or5_path_planning('open',  mainFig)                      打开弹窗
%    or5_path_planning('click', mainFig, col, row, selType)   主窗口鼠标点击分发
%    or5_path_planning('close', mainFig)                      弹窗关闭处理
%    mapOut = or5_path_planning('overlay', mainFig, mapIn)    在地图上叠加道路/路径/起终点
%
%  独立性说明：OR5 直接读取项目自带的 RoadMask.jpg 作为道路栅格，不读取
%  S.sk / S.roadMask 等 OR1 的任何产出。道路栅格存于 S.or5.roadMask。
%  算法：手写图搜索（4 连通 BFS，边权均为 1 像素 = 无权最短路，即 Dijkstra
%        在等权图上的特例），禁用 graphshortestpath 等高级内置函数。
%  吸附：用户点击后，在道路栅格中找欧氏距离最近的道路像素作为起终点。
%  坐标：路网/路径均为像素坐标 [col, row]；显示长度按 S.scale 换算成米。

    switch action
        case 'open'
            do_open(mainFig);
        case 'click'
            do_click(mainFig, varargin{:});
        case 'close'
            do_close(mainFig);
        case 'overlay'
            varargout{1} = do_overlay(mainFig, varargin{1});
    end
end


%% ====================================================================
%   打开弹窗
%% ====================================================================
function do_open(mainFig)
    S = getappdata(mainFig, 'S');

    if isempty(S.mapOrigin)
        uialert(mainFig, '请先加载地图。', '提示');
        return;
    end

    % 加载道路栅格（若未加载）
    if ~isfield(S, 'or5') || isempty(S.or5.roadMask)
        mask = loadRoadMask(mainFig);
        if isempty(mask)
            uialert(mainFig, '未能加载 RoadMask.jpg，无法进行路径规划。', '错误');
            return;
        end
        S = getappdata(mainFig, 'S');   % 重新读，避免覆盖别处改动
        if ~isfield(S, 'or5'), S.or5 = defaultOr5State(); end
        S.or5.roadMask = mask;
        setappdata(mainFig, 'S', S);
    end

    % 弹窗已存在则前置
    if isfield(S, 'or5Fig') && ~isempty(S.or5Fig) && isvalid(S.or5Fig)
        figure(S.or5Fig);
        return;
    end

    or5Fig = uifigure('Name', '路径规划 (OR5)', ...
                      'Position', [180 180 300 480], ...
                      'Resize', 'off');
    setappdata(or5Fig, 'mainFig', mainFig);

    gl = uigridlayout(or5Fig, [20 1]);
    gl.RowHeight = repmat({'fit'}, 20, 1);
    gl.ColumnWidth = {'1x'};

    r = 0;
    function c = addC(type, rowIdx, varargin)
        c = feval(['ui' type], gl, varargin{:});
        c.Layout.Row = rowIdx; c.Layout.Column = 1;
    end

    % ----- 标题 -----
    r = r + 1;
    addC('label', r, 'Text', '路径规划 (OR5)', ...
         'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    r = r + 1;
    addC('label', r, 'Text', '基于 RoadMap 栅格搜索', 'FontSize', 8, 'FontAngle', 'italic');

    % ----- 道路 -----
    r = r + 1;
    addC('label', r, 'Text', '──── 道路 ────', 'FontSize', 11, 'FontWeight', 'bold');
    r = r + 1;
    roadLabel = addC('label', r, 'Text', sprintf('道路像素: %d', sum(S.or5.roadMask(:))), 'FontSize', 9);
    r = r + 1;
    btnToggleRoad = addC('button', r, 'Text', '隐藏道路高亮', ...
        'ButtonPushedFcn', @(~,~) onBtnToggleRoad(or5Fig));

    % ----- 路径 -----
    r = r + 1;
    addC('label', r, 'Text', '──── 路径 ────', 'FontSize', 11, 'FontWeight', 'bold');
    r = r + 1;
    btnSetStart = addC('button', r, 'Text', '设置起点', ...
        'ButtonPushedFcn', @(~,~) onBtnSetStart(or5Fig));
    r = r + 1;
    btnSetEnd = addC('button', r, 'Text', '设置终点', ...
        'ButtonPushedFcn', @(~,~) onBtnSetEnd(or5Fig));
    r = r + 1;
    btnPlan = addC('button', r, 'Text', '规划路径', ...
        'ButtonPushedFcn', @(~,~) onBtnPlan(or5Fig));
    r = r + 1;
    btnClear = addC('button', r, 'Text', '清除路径', ...
        'ButtonPushedFcn', @(~,~) onBtnClear(or5Fig));

    % ----- 信息 -----
    r = r + 1;
    addC('label', r, 'Text', '──── 信息 ────', 'FontSize', 11, 'FontWeight', 'bold');
    r = r + 1;
    startLabel = addC('label', r, 'Text', '起点: 未设置', 'FontSize', 9);
    r = r + 1;
    endLabel = addC('label', r, 'Text', '终点: 未设置', 'FontSize', 9);
    r = r + 1;
    lenLabel = addC('label', r, 'Text', '路径长度: ---', 'FontSize', 9, 'FontWeight', 'bold');

    % ----- 提示 -----
    r = r + 1;
    addC('label', r, 'Text', '点击点自动吸附到最近道路像素', 'FontSize', 8, 'FontAngle', 'italic');
    r = r + 1;
    addC('label', r, 'Text', '绿=最短路径 蓝=起点 红=终点', 'FontSize', 8, 'FontAngle', 'italic');

    % ----- 关闭 -----
    r = r + 1;
    addC('button', r, 'Text', '关闭并返回主窗口', ...
        'ButtonPushedFcn', @(~,~) close(or5Fig));

    % 存句柄
    S = getappdata(mainFig, 'S');
    S.or5.btnToggleRoad = btnToggleRoad;
    S.or5.btnSetStart   = btnSetStart;
    S.or5.btnSetEnd     = btnSetEnd;
    S.or5.btnPlan       = btnPlan;
    S.or5.btnClear      = btnClear;
    S.or5.roadLabel     = roadLabel;
    S.or5.startLabel    = startLabel;
    S.or5.endLabel      = endLabel;
    S.or5.lenLabel      = lenLabel;
    S.or5Fig = or5Fig;
    setappdata(mainFig, 'S', S);

    set(or5Fig, 'CloseRequestFcn', @(~,~) or5_path_planning('close', mainFig));
    set(mainFig, 'CloseRequestFcn', @(~,~) onMainClose_OR5(mainFig));

    or5_updateInfo(mainFig);
    S.fn.refresh(mainFig);
    S.fn.setStatus(mainFig, '路径规划已开启：点「设置起点」后点击地图。');
end


%% ====================================================================
%   关闭弹窗（保留道路与路径，便于重开查看）
%% ====================================================================
function do_close(mainFig)
    S = getappdata(mainFig, 'S');
    S.mode = 'idle';
    if isfield(S, 'or5Fig') && ~isempty(S.or5Fig) && isvalid(S.or5Fig)
        delete(S.or5Fig);
    end
    S.or5Fig = [];
    setappdata(mainFig, 'S', S);
    S.fn.refresh(mainFig);
    S.fn.setStatus(mainFig, '路径规划工具已关闭（道路与路径保留，可重开清除）。');
end


%% ====================================================================
%   鼠标点击分发（由主窗口 onMouseDown 调用）
%% ====================================================================
function do_click(mainFig, col, row, ~)
    S = getappdata(mainFig, 'S');
    switch S.mode
        case 'or5_start'
            handleSetPoint(mainFig, col, row, 'start');
        case 'or5_end'
            handleSetPoint(mainFig, col, row, 'end');
    end
end


%% ====================================================================
%   设置起点/终点：吸附到最近道路像素
%% ====================================================================
function handleSetPoint(mainFig, col, row, which)
    S = getappdata(mainFig, 'S');
    if isempty(S.or5.roadMask)
        S.fn.setStatus(mainFig, '道路栅格未加载。');
        return;
    end
    [r, c] = findNearestRoadPixel(S.or5.roadMask, col, row);
    if r == 0
        S.fn.setStatus(mainFig, '未能找到道路像素。');
        return;
    end
    pt = [c, r];
    if strcmp(which, 'start')
        S.or5.startPt = pt;
    else
        S.or5.endPt = pt;
    end
    S.mode = 'idle';
    setappdata(mainFig, 'S', S);
    or5_updateInfo(mainFig);
    S.fn.refresh(mainFig);
    [wx, wy] = px2worldLocal(S, pt(1), pt(2));
    S.fn.setStatus(mainFig, sprintf('%s已设置 @ (%.1f, %.1f) m（吸附到道路）', which, wx, wy));
end


%% ====================================================================
%   按钮回调
%% ====================================================================
function onBtnToggleRoad(or5Fig)
    mainFig = getappdata(or5Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.or5.showRoad = ~S.or5.showRoad;
    if S.or5.showRoad
        S.or5.btnToggleRoad.Text = '隐藏道路高亮';
    else
        S.or5.btnToggleRoad.Text = '显示道路高亮';
    end
    setappdata(mainFig, 'S', S);
    S.fn.refresh(mainFig);
end

function onBtnSetStart(or5Fig)
    mainFig = getappdata(or5Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.mode = 'or5_start';
    setappdata(mainFig, 'S', S);
    S.fn.setStatus(mainFig, '请点击地图设置起点（自动吸附到最近道路像素）。');
end

function onBtnSetEnd(or5Fig)
    mainFig = getappdata(or5Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.mode = 'or5_end';
    setappdata(mainFig, 'S', S);
    S.fn.setStatus(mainFig, '请点击地图设置终点（自动吸附到最近道路像素）。');
end

function onBtnPlan(or5Fig)
    mainFig = getappdata(or5Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    if isempty(S.or5.startPt) || isempty(S.or5.endPt)
        uialert(or5Fig, '请先设置起点和终点。', '提示');
        return;
    end
    sR = S.or5.startPt(2); sC = S.or5.startPt(1);
    eR = S.or5.endPt(2);   eC = S.or5.endPt(1);
    S.fn.setStatus(mainFig, '正在搜索最短道路路径...');
    drawnow;
    t0 = tic;
    [pathR, pathC, totalPx] = gridBFS(S.or5.roadMask, sR, sC, eR, eC);
    elapsed = toc(t0);
    if isempty(pathR)
        S.or5.pathPx = []; S.or5.pathLen = inf;
        setappdata(mainFig, 'S', S);
        or5_updateInfo(mainFig);
        S.fn.refresh(mainFig);
        uialert(or5Fig, '起点与终点之间没有连通的道路路径。', '无路径');
        return;
    end
    S.or5.pathPx  = [pathC, pathR];          % [col, row]
    S.or5.pathLen = totalPx * S.scale;       % 像素 -> 米
    setappdata(mainFig, 'S', S);
    or5_updateInfo(mainFig);
    S.fn.refresh(mainFig);
    S.fn.setStatus(mainFig, sprintf('最短路径: %d 像素, 长度 %.2f m (耗时 %.2f s)', ...
        totalPx, S.or5.pathLen, elapsed));
end

function onBtnClear(or5Fig)
    mainFig = getappdata(or5Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.or5.startPt = []; S.or5.endPt = [];
    S.or5.pathPx = []; S.or5.pathLen = 0;
    setappdata(mainFig, 'S', S);
    or5_updateInfo(mainFig);
    S.fn.refresh(mainFig);
    S.fn.setStatus(mainFig, '路径与起终点已清除（道路高亮保留）。');
end


%% ====================================================================
%   信息标签更新
%% ====================================================================
function or5_updateInfo(mainFig)
    S = getappdata(mainFig, 'S');
    if ~isfield(S, 'or5') || ~isfield(S.or5, 'startLabel'), return; end
    o = S.or5;
    if ~isempty(o.startPt)
        [wx, wy] = px2worldLocal(S, o.startPt(1), o.startPt(2));
        o.startLabel.Text = sprintf('起点: (%.1f, %.1f) m', wx, wy);
    else
        o.startLabel.Text = '起点: 未设置';
    end
    if ~isempty(o.endPt)
        [wx, wy] = px2worldLocal(S, o.endPt(1), o.endPt(2));
        o.endLabel.Text = sprintf('终点: (%.1f, %.1f) m', wx, wy);
    else
        o.endLabel.Text = '终点: 未设置';
    end
    if isinf(o.pathLen)
        o.lenLabel.Text = '路径长度: 无连通路径';
    elseif o.pathLen > 0
        o.lenLabel.Text = sprintf('路径长度: %.2f m', o.pathLen);
    else
        o.lenLabel.Text = '路径长度: ---';
    end
end


%% ====================================================================
%   地图叠加（道路高亮 + 路径 + 起终点），由 main.m 的 buildBaseMap 调用
%% ====================================================================
function mapOut = do_overlay(mainFig, mapIn)
    S = getappdata(mainFig, 'S');
    mapOut = mapIn;
    if ~isfield(S, 'or5'), return; end
    o = S.or5;
    [H, W, ~] = size(mapOut);
    % 1. 道路高亮（淡青色，区别于 OR1 的蓝路）
    if o.showRoad && ~isempty(o.roadMask)
        m = o.roadMask;
        R = double(mapOut(:,:,1)); G = double(mapOut(:,:,2)); B = double(mapOut(:,:,3));
        R(m) = R(m)*0.5 + 20;
        G(m) = G(m)*0.5 + 90;
        B(m) = B(m)*0.5 + 120;
        mapOut = uint8(cat(3, R, G, B));
    end
    % 2. 最短路径：亮绿色加粗线
    if ~isempty(o.pathPx)
        pathColor = uint8([0 255 0]);
        for k = 1:size(o.pathPx, 1)
            mapOut = stampSquare(mapOut, o.pathPx(k,1), o.pathPx(k,2), 2, pathColor, W, H);
        end
    end
    % 3. 起点（蓝）/ 终点（红）
    if ~isempty(o.startPt)
        mapOut = stampSquare(mapOut, o.startPt(1), o.startPt(2), 4, uint8([0 120 255]), W, H);
    end
    if ~isempty(o.endPt)
        mapOut = stampSquare(mapOut, o.endPt(1), o.endPt(2), 4, uint8([255 0 0]), W, H);
    end
end


%% ====================================================================
%   栅格最短路：4 连通 BFS（手写图搜索，等权图上等价于 Dijkstra）
%   节点 = 道路像素；边 = 4 连通邻居；边权 = 1 像素。
%   用 bounding box 限制搜索区域以提速；box 内无路径则回退全图。
%% ====================================================================
function [pathR, pathC, totalPx] = gridBFS(roadMask, sR, sC, eR, eC)
    [H, W] = size(roadMask);
    % 先在 bounding box 内搜索（margin 像素，覆盖常见绕路）
    margin = 150;
    rMin = max(1, min(sR, eR) - margin); rMax = min(H, max(sR, eR) + margin);
    cMin = max(1, min(sC, eC) - margin); cMax = min(W, max(sC, eC) + margin);
    [pathR, pathC, totalPx] = bfsInBox(roadMask, rMin, rMax, cMin, cMax, sR, sC, eR, eC);
    if isempty(pathR)
        % 回退全图（兜底，处理绕路超出 box 的情况）
        [pathR, pathC, totalPx] = bfsInBox(roadMask, 1, H, 1, W, sR, sC, eR, eC);
    end
end

function [pathR, pathC, totalPx] = bfsInBox(roadMask, rMin, rMax, cMin, cMax, sR, sC, eR, eC)
%BFSINBOX  在指定矩形区域内做 4 连通 BFS，返回路径像素坐标与步数
    sub = roadMask(rMin:rMax, cMin:cMax);
    [sH, sW] = size(sub);
    lsR = sR - rMin + 1; lsC = sC - cMin + 1;
    leR = eR - rMin + 1; leC = eC - cMin + 1;
    % 起终点必须落在道路像素上
    if lsR < 1 || lsR > sH || lsC < 1 || lsC > sW || ~sub(lsR, lsC) || ...
       leR < 1 || leR > sH || leC < 1 || leC > sW || ~sub(leR, leC)
        pathR = []; pathC = []; totalPx = inf; return;
    end
    % 同点
    if lsR == leR && lsC == leC
        pathR = sR; pathC = sC; totalPx = 0; return;
    end

    % BFS：用一维数组当队列，prev 用线性索引记录前驱
    N = sH * sW;
    prev = zeros(N, 1);          % 0=未访问
    queue = zeros(N, 1);         % 预分配队列（存线性索引）
    head = 1; tail = 1;
    sLin = lsR + (lsC - 1) * sH;
    eLin = leR + (leC - 1) * sH;
    prev(sLin) = -1;             % 标记起点已访问（非 0）
    queue(tail) = sLin; tail = tail + 1;

    % 4 连通方向（行偏移、列偏移）
    dr = [-1; 1; 0; 0];
    dc = [0; 0; -1; 1];

    found = false;
    while head < tail
        cur = queue(head); head = head + 1;
        if cur == eLin
            found = true; break;
        end
        cr = mod(cur - 1, sH) + 1;
        cc = floor((cur - 1) / sH) + 1;
        for k = 1:4
            nr = cr + dr(k); nc = cc + dc(k);
            if nr < 1 || nr > sH || nc < 1 || nc > sW, continue; end
            if ~sub(nr, nc), continue; end
            nLin = nr + (nc - 1) * sH;
            if prev(nLin) ~= 0, continue; end
            prev(nLin) = cur;
            queue(tail) = nLin; tail = tail + 1;
        end
    end

    if ~found
        pathR = []; pathC = []; totalPx = inf; return;
    end

    % 回溯路径（局部线性索引 -> 全局 row/col）
    pathLin = eLin;
    cur = eLin;
    while cur ~= sLin
        cur = prev(cur);
        pathLin = [cur; pathLin];   %#ok<AGROW>
    end
    pathR = zeros(numel(pathLin), 1);
    pathC = zeros(numel(pathLin), 1);
    for i = 1:numel(pathLin)
        lr = mod(pathLin(i) - 1, sH) + 1;
        lc = floor((pathLin(i) - 1) / sH) + 1;
        pathR(i) = lr + rMin - 1;
        pathC(i) = lc + cMin - 1;
    end
    totalPx = numel(pathLin) - 1;   % 步数 = 像素数 - 1（4 连通每步 1 像素）
end


%% ====================================================================
%   最近道路像素（向量化求最小欧氏距离）
%% ====================================================================
function [r, c] = findNearestRoadPixel(roadMask, col, row)
%FINDNEARESTROADPIXEL  返回离 (col,row) 最近的道路像素 [r,c]；无道路则 [0,0]
    [rr, cc] = find(roadMask);
    if isempty(rr), r = 0; c = 0; return; end
    d2 = (cc - col).^2 + (rr - row).^2;
    [~, i] = min(d2);
    r = rr(i); c = cc(i);
end


%% ====================================================================
%   道路栅格加载（直接读盘，与主程序 basicRoadMask 解耦，保持 OR5 独立）
%   优先尝试与 main.m 一致的标准文件 RoadMask_Optimized.png，回退到 RoadMask.jpg。
%% ====================================================================
function mask = loadRoadMask(mainFig)
    S = getappdata(mainFig, 'S');
    mfileDir = fileparts(mfilename('fullpath'));
    if isempty(mfileDir), mfileDir = '.'; end
    img = [];
    % 与 main.m 的加载顺序一致：先 RoadMask_Optimized.png，再 RoadMask.jpg
    candidates = {'RoadMask_Optimized.png', 'RoadMask.jpg'};
    for i = 1:numel(candidates)
        p = fullfile(mfileDir, candidates{i});
        if isfile(p)
            img = imread(p);
            break;
        end
    end
    if isempty(img), mask = []; return; end
    if size(img, 3) == 3
        g = (double(img(:,:,1)) + double(img(:,:,2)) + double(img(:,:,3))) / 3;
    else
        g = double(img);
    end
    mask = g > 160;
    % 保证与地图尺寸一致
    [mH, mW] = size(mask);
    if mH ~= S.mapH || mW ~= S.mapW
        mask = [];     % 尺寸不匹配，放弃
    end
end


%% ====================================================================
%   本地工具（main.m 中为 local function，跨文件不可见，故自带副本）
%% ====================================================================
function s = defaultOr5State()
%DEFAULTOR5STATE  OR5 独立状态初始化
    s.roadMask = [];
    s.showRoad = true;
    s.startPt = []; s.endPt = [];
    s.pathPx = []; s.pathLen = 0;
end

function [wx, wy] = px2worldLocal(S, col, row)
%PX2WORLDLOCAL  像素 -> 世界坐标（米），原点在图像左下角
    wx = col * S.scale;
    wy = (S.mapH - row) * S.scale;
end

function map = stampSquare(map, cx, cy, radius, color, W, H)
%STAMPSQUARE  在 (cx,cy) 处盖一个 (2*radius+1) 的实心方块
    cc0 = round(cx); rr0 = round(cy);
    for dr = -radius:radius
        for dc = -radius:radius
            rr = rr0 + dr; cc = cc0 + dc;
            if cc >= 1 && cc <= W && rr >= 1 && rr <= H
                map(rr, cc, :) = color;
            end
        end
    end
end

function onMainClose_OR5(mainFig)
%ONMAINCLOSE_OR5  主窗口关闭时自动清理 OR5 弹窗（不触发递归 close）
    try
        S = getappdata(mainFig, 'S');
        if isfield(S, 'or5Fig') && ~isempty(S.or5Fig) && isvalid(S.or5Fig)
            set(S.or5Fig, 'CloseRequestFcn', []);   % 剥离回调防止递归
            delete(S.or5Fig);
        end
    catch
    end
    try
        delete(mainFig);
    catch
    end
end
