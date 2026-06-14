function fig = main()
%MAIN  智能导航 UI 主入口
%  运行：直接在命令行输入 main 即可启动。
%  返回 figure 句柄（可选，便于测试）。
%  说明：本程序为 ISE 333 课程项目，纯手写实现（禁止高级内置函数）。
%        启动后所有操作均通过 UI 完成，无需命令行干预。

    %% ---------- 1. 创建主窗口 ----------
    fig = uifigure('Name', '智能导航 UI', ...
                   'Position', [100 100 1200 760], ...
                   'AutoResizeChildren','off', ...
                   'WindowButtonDownFcn', @onMouseDown, ...
                   'WindowButtonUpFcn',   @onMouseUp, ...
                   'SizeChangedFcn', @onResize);

    %% ---------- 2. 整体布局：左面板(320px) + 右画布（用 Position 定位） ----------
    panelWidth = 320;
    % 左侧控制面板
    panel = uipanel(fig, 'Title','', 'Units','pixels', ...
                    'Position', [0 0 panelWidth 760], ...
                    'BorderType','none', 'Tag','ctrlPanel');
    pnlChild = uigridlayout(panel, [1 1]);   % panel 内嵌 grid，便于后续排列控件

    % 右侧画布
    ax = uiaxes(fig, 'Units','pixels', ...
                'Position', [panelWidth 0 1200-panelWidth 760]);
    ax.Tag = 'mapAxes';
    set(ax, 'XLimMode','manual', 'YLimMode','manual', ...
            'XTick',[], 'YTick',[], 'Box','off', ...
            'XColor','none','YColor','none');
    ax.Toolbar.Visible = 'off';   % 关闭自带工具栏，避免误用缩放等

    %% ---------- 3. 初始化全局状态 S ----------
    S = struct();
    S.fig       = fig;
    S.ax        = ax;
    S.panel     = panel;     % uipanel（用于 onResize 调整 Position）
    S.pnlGrid   = pnlChild;  % gridlayout（用于往里放控件）
    S.mapOrigin = [];        % 原始地图矩阵（只读）
    S.mapDisplay= [];        % 当前显示用副本
    S.scale     = 1.7;       % 1 像素 = 1.7 米
    S.mapW      = 1404;      % 图像宽度（列数）—— 横向地图
    S.mapH      = 803;       % 图像高度（行数）
    S.mode      = 'idle';    % 交互模式状态机

    % —— OR1 道路骨架相关（后续步骤填充） ——
    S.sk.nodes  = zeros(0,2);  % [N x 2]，每行 [col, row]
    S.sk.edges  = zeros(0,2,'int32'); % [M x 2]，每行 [nodeIdx_i, nodeIdx_j] (1-based)
    S.roadMask  = [];          % [mapH x mapW logical]
    S.roadHalfWidth = 2;       % 道路半宽（像素），由滑块调整

    % —— 车辆相关（后续步骤） ——
    S.vehicles  = struct('id',{},'cx',{},'cy',{},'angle',{},'dispScale',{});
    S.nextIVid  = 1;

    % —— 测量暂存 ——
    S.measurePts = zeros(0,2);   % [K x 2]
    S.sketchChain = [];          % 当前折线正在输入的节点序号列表

    setappdata(fig, 'S', S);

    %% ---------- 4. 构建左侧控制面板 ----------
    h = buildPanel(pnlChild, fig);   % 在 gridlayout 里放控件，返回句柄
    S.handles = h;
    setS(fig, S);

    %% ---------- 5. 自动加载地图（路径相对于 main.m 所在文件夹） ----------
    mfileDir = fileparts(mfilename('fullpath'));
    if isempty(mfileDir), mfileDir = '.'; end
    mapPath = fullfile(mfileDir, 'MapForUI.jpg');
    if isfile(mapPath)
        S = getS(fig);
        S.mapOrigin  = imread(mapPath);
        S.mapDisplay = S.mapOrigin;
        [S.mapH, S.mapW, ~] = size(S.mapOrigin);
        setS(fig, S);
    end
    refreshView(fig);
    setStatus(fig, '就绪：已加载地图。点击地图任意点可查看世界坐标。');
end % main() 返回 fig


%% ====================================================================
%   左侧控制面板构建
%   返回 handles 结构体，包含所有需后续访问的控件句柄
%% ====================================================================
function h = buildPanel(pnl, fig)
    rows = 28;
    pnl.RowHeight = repmat({'fit'}, rows, 1);
    pnl.ColumnWidth = {'1x'};
    h = struct();
    r = 0;

    % 辅助函数：创建控件并放置到指定行
    function c = addC(type, rowIdx, varargin)
        c = feval(['ui' type], pnl, varargin{:});
        c.Layout.Row = rowIdx; c.Layout.Column = 1;
    end

    % ----- 标题 -----
    r = r + 1;
    addC('label', r, 'Text','智能导航 UI', 'FontSize',16, 'FontWeight','bold', ...
            'HorizontalAlignment','center');
    r = r + 1;
    addC('label', r, 'Text','1像素 = 1.7 米   地图: 1404×803', 'FontSize',9);

    % ----- 地图分组 -----
    r = r + 1;
    addC('label', r, 'Text','──── 地图 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    addC('label', r, 'Text','旋转角度 (度):');
    r = r + 1;
    h.rotEdit = addC('editfield', r, 'numeric', 'Value',0, 'Limits',[-360 360], ...
                     'ValueChangedFcn', @(s,e) onRotChanged(fig,s));

    % ----- 骨架分组 (OR1) -----
    r = r + 1;
    addC('label', r, 'Text','──── 道路骨架 (OR1) ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.btnSketch = addC('button', r, 'Text','开始提取骨架', ...
                       'ButtonPushedFcn', @(s,e) onBtnSketch(fig));
    r = r + 1;
    h.btnErase = addC('button', r, 'Text','擦除线段', ...
                      'ButtonPushedFcn', @(s,e) onBtnErase(fig));
    r = r + 1;
    h.btnClearSkeleton = addC('button', r, 'Text','清空骨架', ...
                              'ButtonPushedFcn', @(s,e) onBtnClearSkeleton(fig));
    r = r + 1;
    h.btnShowSkeleton = addC('button', r, 'Text','显示/刷新骨架', ...
                             'ButtonPushedFcn', @(s,e) onBtnShowSkeleton(fig));
    r = r + 1;
    addC('label', r, 'Text','道路半宽(像素):', 'FontSize',9);
    r = r + 1;
    h.roadWidthSlider = addC('slider', r, 'Value',2, 'Limits',[1 15], ...
                             'MajorTicks',[1 5 10 15], ...
                             'ValueChangedFcn', @(s,e) onRoadWidthChanged(fig,s));
    r = r + 1;
    h.roadWidthValue = addC('label', r, 'Text','当前: 2 像素', 'FontSize',9);
    r = r + 1;
    h.btnGenMask = addC('button', r, 'Text','生成道路掩膜', ...
                        'ButtonPushedFcn', @(s,e) onBtnGenMask(fig));
    r = r + 1;
    h.btnShowRoad = addC('button', r, 'Text','显示道路区', ...
                         'ButtonPushedFcn', @(s,e) onBtnShowRoad(fig));
    r = r + 1;
    addC('label', r, 'Text','提示: sketch模式 左键画点/右键结束折线', 'FontSize',8, 'FontAngle','italic');

    % ----- 智能车分组 -----
    r = r + 1;
    addC('label', r, 'Text','──── 智能车 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.btnLoadIV = addC('button', r, 'Text','加载车辆', ...
                       'ButtonPushedFcn', @(s,e) onBtnLoadIV(fig));
    r = r + 1;
    h.btnRemoveIV = addC('button', r, 'Text','移除车辆', ...
                         'ButtonPushedFcn', @(s,e) onBtnRemoveIV(fig));
    r = r + 1;
    addC('label', r, 'Text','选择车辆:', 'FontSize',9);
    r = r + 1;
    h.ivDropdown = addC('dropdown', r, 'Items', {'(无车辆)'}, ...
                        'Value', '(无车辆)');
    r = r + 1;
    addC('label', r, 'Text','朝向调整(度):', 'FontSize',9);
    r = r + 1;
    h.angleSlider = addC('slider', r, 'Value',0, 'Limits',[0 360], ...
                         'MajorTicks',[0 90 180 270 360], ...
                         'ValueChangedFcn', @(s,e) onAngleChanged(fig,s));
    r = r + 1;
    h.angleValue = addC('label', r, 'Text','当前: 0°', 'FontSize',9);
    r = r + 1;
    h.btnReportIV = addC('button', r, 'Text','报告位置', ...
                         'ButtonPushedFcn', @(s,e) onBtnReportIV(fig));
    r = r + 1;
    addC('label', r, 'Text','提示: 加载前请先生成道路掩膜', 'FontSize',8, 'FontAngle','italic');

    % ----- 测量分组（占位） -----
    r = r + 1;
    addC('label', r, 'Text','──── 测量 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    addC('label', r, 'Text','(步骤F 实现)', 'FontSize',8, 'FontAngle','italic');

    % ----- 坐标显示 -----
    r = r + 1;
    addC('label', r, 'Text','──── 坐标 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.coordX = addC('label', r, 'Text','X: --- m');
    r = r + 1;
    h.coordY = addC('label', r, 'Text','Y: --- m');

    % ----- 状态栏 -----
    r = r + 1;
    h.statusBar = addC('label', r, 'Text','当前: ---', 'FontAngle','italic');
end


%% ====================================================================
%   鼠标交互（本步骤：仅显示坐标）
%% ====================================================================
function onMouseDown(fig, ~)
%ONMOUSEDOWN  主鼠标按下回调，按 mode + 按键类型分发
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    pt = getPointerOnAxes(fig, S.ax);
    if isempty(pt), return; end
    col = pt(1); row = pt(2);
    selType = get(fig, 'SelectionType');   % 'normal'=左键 'alt'=右键

    % 始终更新坐标显示
    [wx, wy] = px2world(fig, col, row);
    if isfield(S,'handles')
        try
            S.handles.coordX.Text = sprintf('X: %.2f m', wx);
            S.handles.coordY.Text = sprintf('Y: %.2f m', wy);
        catch; end
    end

    % 按模式分发
    switch S.mode
        case 'sketch'
            if strcmp(selType, 'alt')      % 右键：结束当前折线
                S.sketchChain = [];
                setS(fig, S);
                setStatus(fig, '折线已结束，可开始新的折线（左键画点）。');
            else                            % 左键：添加节点
                handleSketchClick(fig, col, row);
            end
        case 'erase'
            handleEraseClick(fig, col, row);
        case 'loadIV'
            handleLoadIVClick(fig, col, row);
        otherwise
            % idle：仅显示坐标，已在上面处理
    end
end

function onMouseUp(fig, ~)
    % 预留：拖拽相关
end


%% ====================================================================
%   骨架交互处理
%% ====================================================================
function handleSketchClick(fig, col, row)
%HANDLESKETCHCLICK  sketch 模式下左键添加节点并连接
    S = getS(fig);
    % 追加新节点
    S.sk.nodes(end+1, :) = [col, row];   %#ok<AGROW>
    nodeIdx = size(S.sk.nodes, 1);
    % 如果当前折线非空，连接上一节点
    if ~isempty(S.sketchChain)
        prev = S.sketchChain(end);
        S.sk.edges(end+1, :) = [prev, nodeIdx];  %#ok<AGROW>
    end
    S.sketchChain(end+1) = nodeIdx;      %#ok<AGROW>
    setS(fig, S);
    drawSkeleton(fig);
    setStatus(fig, sprintf('已添加节点 #%d（折线内第 %d 点）', nodeIdx, numel(S.sketchChain)));
end

function handleEraseClick(fig, col, row)
%HANDLEERASECLICK  erase 模式下删除离点击点最近的整条线段
    S = getS(fig);
    if isempty(S.sk.edges)
        setStatus(fig, '无骨架可擦除。');
        return;
    end
    P = [col, row];
    threshold = 6;   % 像素，命中阈值
    bestIdx = 0; bestDist = inf;
    for i = 1:size(S.sk.edges, 1)
        ni = S.sk.edges(i, 1); nj = S.sk.edges(i, 2);
        A = S.sk.nodes(ni, :); B = S.sk.nodes(nj, :);
        d = ptToSegDist(P, A, B);
        if d < bestDist
            bestDist = d; bestIdx = i;
        end
    end
    if bestIdx > 0 && bestDist < threshold
        S.sk.edges(bestIdx, :) = [];   % 删除该边
        % 清理孤立节点：删除不与任何 edge 相连的节点
        S = cleanupNodes(S);
        setS(fig, S);
        drawSkeleton(fig);
        setStatus(fig, sprintf('已擦除线段（最近距离 %.1f 像素）', bestDist));
    else
        setStatus(fig, sprintf('未命中任何线段（最近 %.1f 像素），请靠近线段点击。', bestDist));
    end
end

function S = cleanupNodes(S)
%CLEANUPNODES  删除孤立节点并重映射 edge 索引
    nNodes = size(S.sk.nodes, 1);
    if nNodes == 0, return; end
    used = false(nNodes, 1);
    if ~isempty(S.sk.edges)
        used(S.sk.edges(:)) = true;
    end
    keepIdx = find(used);
    % 建立旧索引 -> 新索引的映射表
    newMap = zeros(nNodes, 1);
    newMap(keepIdx) = 1:numel(keepIdx);
    % 重映射 edges
    if ~isempty(S.sk.edges)
        S.sk.edges(:,1) = newMap(S.sk.edges(:,1));
        S.sk.edges(:,2) = newMap(S.sk.edges(:,2));
    end
    S.sk.nodes = S.sk.nodes(keepIdx, :);
end


%% ====================================================================
%   骨架按钮回调
%% ====================================================================
function onBtnSketch(fig)
    S = getS(fig);
    S.mode = 'sketch';
    S.sketchChain = [];
    setS(fig, S);
    setStatus(fig, '骨架提取模式：左键连续画点，右键结束当前折线。');
end

function onBtnErase(fig)
    S = getS(fig);
    S.mode = 'erase';
    setS(fig, S);
    setStatus(fig, '擦除模式：点击/靠近要删除的线段（整条删除）。');
end

function onBtnClearSkeleton(fig)
    S = getS(fig);
    S.sk.nodes = zeros(0,2);
    S.sk.edges = zeros(0,2,'int32');
    S.sketchChain = [];
    S.mode = 'idle';
    setS(fig, S);
    refreshView(fig);    % 恢复纯地图
    setStatus(fig, '骨架已清空。');
end

function onBtnShowSkeleton(fig)
    S = getS(fig);
    S.mode = 'idle';
    setS(fig, S);
    drawSkeleton(fig);
    setStatus(fig, sprintf('骨架已显示： %d 节点, %d 线段', ...
              size(S.sk.nodes,1), size(S.sk.edges,1)));
end

%% ====================================================================
%   道路掩膜相关回调（OR1 步骤C）
%% ====================================================================
function onRoadWidthChanged(fig, src)
    S = getS(fig);
    S.roadHalfWidth = round(src.Value);
    setS(fig, S);
    if isfield(S.handles, 'roadWidthValue')
        S.handles.roadWidthValue.Text = sprintf('当前: %d 像素', S.roadHalfWidth);
    end
end

function onBtnGenMask(fig)
    S = getS(fig);
    if isempty(S.sk.edges)
        setStatus(fig, '无骨架！请先提取骨架再生成掩膜。');
        uialert(fig, '请先点击"开始提取骨架"画出道路骨架，再生成掩膜。', '提示');
        return;
    end
    setStatus(fig, sprintf('正在生成道路掩膜（半宽=%d像素）...', S.roadHalfWidth));
    drawnow;   % 让状态栏立即刷新
    S.roadMask = genRoadMask(S.sk.nodes, S.sk.edges, S.roadHalfWidth, S.mapW, S.mapH);
    setS(fig, S);
    roadPx = sum(S.roadMask(:));
    setStatus(fig, sprintf('道路掩膜已生成： %d 像素（半宽=%d）。点击"显示道路区"查看。', ...
              roadPx, S.roadHalfWidth));
end

function onBtnShowRoad(fig)
    S = getS(fig);
    if isempty(S.roadMask)
        setStatus(fig, '请先点击"生成道路掩膜"。');
        return;
    end
    S.mode = 'idle';
    setS(fig, S);
    drawRoadArea(fig);
    setStatus(fig, sprintf('道路区已显示（半透明蓝色覆盖）。'));
end

function mask = genRoadMask(nodes, edges, halfWidth, mapW, mapH)
%GENROADMASK  根据骨架生成道路掩膜（手写膨胀）
%  对每条边，遍历其 bounding box(+margin) 内的像素，
%  距离 < halfWidth 则标记为道路。
    mask = false(mapH, mapW);
    tol = halfWidth + 1;
    for i = 1:size(edges, 1)
        ni = edges(i,1); nj = edges(i,2);
        A = nodes(ni,:); B = nodes(nj,:);
        % bounding box
        cMin = max(1, floor(min(A(1),B(1)) - tol));
        cMax = min(mapW, ceil(max(A(1),B(1)) + tol));
        rMin = max(1, floor(min(A(2),B(2)) - tol));
        rMax = min(mapH, ceil(max(A(2),B(2)) + tol));
        % 遍历 box 内每个像素
        for r = rMin:rMax
            for c = cMin:cMax
                if ~mask(r, c)
                    d = ptToSegDist([c, r], A, B);
                    if d <= halfWidth
                        mask(r, c) = true;
                    end
                end
            end
        end
    end
end

function drawRoadArea(fig)
%DRAWROADAREA  在地图上半透明覆盖道路区（蓝色）
    S = getS(fig);
    if isempty(S.mapOrigin) || isempty(S.roadMask), return; end
    S.mapDisplay = S.mapOrigin;
    % 半透明蓝色覆盖：newColor = old*0.5 + blue*0.5
    overlayR = 30; overlayG = 100; overlayB = 220;
    m = S.roadMask;
    R = double(S.mapDisplay(:,:,1));
    G = double(S.mapDisplay(:,:,2));
    B = double(S.mapDisplay(:,:,3));
    R(m) = R(m)*0.5 + overlayR*0.5;
    G(m) = G(m)*0.5 + overlayG*0.5;
    B(m) = B(m)*0.5 + overlayB*0.5;
    S.mapDisplay = uint8(cat(3, R, G, B));
    % 同时画骨架（红/黄）以便对比
    drawSkeletonOnMap(fig);
end

function drawSkeletonOnMap(fig)
%DRAWSKELETONONMAP  在当前 mapDisplay 上叠加骨架（不重置 mapDisplay）
    S = getS(fig);
    if isempty(S.mapDisplay), return; end
    lineColor = uint8([255 0 0]);
    for i = 1:size(S.sk.edges, 1)
        ni = S.sk.edges(i,1); nj = S.sk.edges(i,2);
        A = S.sk.nodes(ni,:); B = S.sk.nodes(nj,:);
        pxs = bresenham(A(1), A(2), B(1), B(2));
        for k = 1:size(pxs,1)
            c = pxs(k,1); r = pxs(k,2);
            if c>=1 && c<=S.mapW && r>=1 && r<=S.mapH
                S.mapDisplay(r, c, :) = lineColor;
            end
        end
    end
    nodeColor = uint8([255 255 0]);
    for i = 1:size(S.sk.nodes, 1)
        c = round(S.sk.nodes(i,1)); r = round(S.sk.nodes(i,2));
        for dr = -1:1
            for dc = -1:1
                rr = r+dr; cc = c+dc;
                if cc>=1 && cc<=S.mapW && rr>=1 && rr<=S.mapH
                    S.mapDisplay(rr, cc, :) = nodeColor;
                end
            end
        end
    end
    setS(fig, S);
    refreshView(fig);
end

%% ====================================================================
%   智能车 (IV) 相关
%% ====================================================================
function handleLoadIVClick(fig, col, row)
%HANDLELOADIVCLICK  loadIV 模式下点击地图加载车辆
    S = getS(fig);
    % 道路校验：必须有 roadMask
    if isempty(S.roadMask)
        setStatus(fig, '请先生成道路掩膜，再加载车辆。');
        uialert(S.fig, '请先点击"生成道路掩膜"。', '提示');
        return;
    end
    rc = round(row); cc = round(col);
    if rc < 1 || rc > S.mapH || cc < 1 || cc > S.mapW
        setStatus(fig, '点击点超出地图范围。');
        return;
    end
    if ~S.roadMask(rc, cc)
        setStatus(fig, sprintf('无效点 (%.0f,%.0f)：不在道路上！', col, row));
        uialert(S.fig, '该点不在道路上，无法加载车辆。', '加载失败');
        return;
    end
    % 有效：添加车辆
    angle = 0;
    if isfield(S.handles,'angleSlider') && isvalid(S.handles.angleSlider)
        angle = S.handles.angleSlider.Value;
    end
    v.id = S.nextIVid;
    v.cx = col; v.cy = row;
    v.angle = angle;
    v.dispScale = 3;   % 显示放大倍数（真实尺寸太小）
    S.vehicles(end+1) = v;   %#ok<AGROW>
    S.nextIVid = S.nextIVid + 1;
    S.mode = 'idle';
    setS(fig, S);
    drawAllVehicles(fig);
    updateIVDropdown(fig);
    [wx, wy] = px2world(fig, col, row);
    setStatus(fig, sprintf('车辆 #%d 已加载 @ (%.1f, %.1f)m，朝向 %.0f°', ...
              v.id, wx, wy, v.angle));
end

function drawAllVehicles(fig)
%DRAWALLVEHICLES  重绘地图（原图+骨架+所有车辆）
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    S.mapDisplay = S.mapOrigin;
    setS(fig, S);
    % 叠加骨架（如果有的话）
    if ~isempty(S.sk.edges)
        drawSkeletonOnMap(fig);
    end
    % 叠加每辆车
    S = getS(fig);
    for i = 1:numel(S.vehicles)
        S.mapDisplay = drawIV(S.mapDisplay, ...
            S.vehicles(i).cx, S.vehicles(i).cy, ...
            S.vehicles(i).angle, S.vehicles(i).dispScale, ...
            S.mapW, S.mapH, S.scale);
    end
    setS(fig, S);
    refreshView(fig);
end

function mapOut = drawIV(mapIn, cx, cy, angleDeg, dispScale, mapW, mapH, scale)
%DRAWIV  手搓绘制单辆 IV（旋转矩形）到地图矩阵上
%  真实 IV: 8m x 3m -> 像素 8/1.7 x 3/1.7 ≈ 4.7 x 1.8 -> x dispScale
    L = (8 / scale) * dispScale;   % 长（像素）
    Wd = (3 / scale) * dispScale;  % 宽（像素）
    % 局部坐标角点 [x, y]（长边沿 X 轴）
    corners = [-L/2 -Wd/2; L/2 -Wd/2; L/2 Wd/2; -L/2 Wd/2];
    % 旋转矩阵（手写）
    th = deg2rad(angleDeg);
    R = [cos(th) -sin(th); sin(th) cos(th)];
    rotCorners = corners * R';   % 旋转
    % 平移到 (cx, cy) -> 像素坐标 [col, row]
    ptsPx = rotCorners + [cx, cy];
    % 用扫描线填充多边形（手写）
    mapOut = mapIn;
    bodyColor = uint8([0 200 0]);   % 绿色车体
    % 计算 bounding box
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
    % 画车头指示（前方向画一个亮色点）
    frontX = cx + (L/2) * cos(th);
    frontY = cy + (L/2) * sin(th);
    fr = round(frontY); fc = round(frontX);
    if fc>=1 && fc<=mapW && fr>=1 && fr<=mapH
        mapOut(fr, fc, :) = uint8([255 255 0]);
    end
end

function inside = pointInPolygon(pt, poly)
%POINTINPOLYGON  射线法判断点是否在多边形内（手写）
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

function updateIVDropdown(fig)
%UPDATEIVDROPDOWN  更新车辆下拉列表
    S = getS(fig);
    items = {'(无车辆)'};
    if ~isempty(S.vehicles)
        items = arrayfun(@(v) sprintf('#%d (%.0f,%.0f)', v.id, v.cx, v.cy), ...
                         S.vehicles, 'UniformOutput', false);
    end
    dd = S.handles.ivDropdown;
    dd.Items = items;
    if ~isempty(S.vehicles)
        dd.Value = items{end};
    else
        dd.Value = '(无车辆)';
    end
end

function onBtnLoadIV(fig)
    S = getS(fig);
    if isempty(S.roadMask)
        uialert(fig, '请先提取骨架并生成道路掩膜，再加载车辆。', '提示');
        return;
    end
    S.mode = 'loadIV';
    setS(fig, S);
    setStatus(fig, '加载车辆模式：点击地图上道路区域放置车辆。');
end

function onBtnRemoveIV(fig)
    S = getS(fig);
    if isempty(S.vehicles)
        setStatus(fig, '无车辆可移除。');
        return;
    end
    sel = S.handles.ivDropdown.Value;
    % 解析 "#id ..."
    tok = regexp(sel, '^#(\d+)', 'match', 'once');
    if isempty(tok)
        setStatus(fig, '请先在下拉框选择要移除的车辆。');
        return;
    end
    rmId = str2double(regexp(sel, '#(\d+)', 'tokens', 'once'));
    idx = find(arrayfun(@(v) v.id==rmId, S.vehicles), 1);
    if isempty(idx)
        setStatus(fig, '未找到该车辆。');
        return;
    end
    S.vehicles(idx) = [];
    setS(fig, S);
    drawAllVehicles(fig);
    updateIVDropdown(fig);
    setStatus(fig, sprintf('车辆 #%d 已移除。', rmId));
end

function onAngleChanged(fig, src)
    S = getS(fig);
    S.handles.angleValue.Text = sprintf('当前: %.0f°', src.Value);
    % 如果有选中的车辆，更新其角度并重绘
    if ~isempty(S.vehicles)
        sel = S.handles.ivDropdown.Value;
        tok = regexp(sel, '#(\d+)', 'tokens', 'once');
        if ~isempty(tok)
            id = str2double(tok{1});
            idx = find(arrayfun(@(v) v.id==id, S.vehicles), 1);
            if ~isempty(idx)
                S.vehicles(idx).angle = src.Value;
                setS(fig, S);
                drawAllVehicles(fig);
            end
        end
    end
end

function onBtnReportIV(fig)
    S = getS(fig);
    if isempty(S.vehicles)
        setStatus(fig, '无车辆。');
        return;
    end
    lines = cell(numel(S.vehicles),1);
    for i = 1:numel(S.vehicles)
        [wx, wy] = px2world(fig, S.vehicles(i).cx, S.vehicles(i).cy);
        lines{i} = sprintf('车辆 #%d: 位置(%.1f, %.1f)m  朝向 %.0f°', ...
                           S.vehicles(i).id, wx, wy, S.vehicles(i).angle);
    end
    msg = strjoin(lines, newline);
    uialert(fig, msg, '所有车辆位置报告');
    setStatus(fig, sprintf('已报告 %d 辆车的位置。', numel(S.vehicles)));
end

function onResize(fig, ~)
%ONRESIZE  窗口大小改变时，重排左面板和右画布
    S = getS(fig);
    if ~isfield(S,'panel') || ~isfield(S,'ax'), return; end
    pos = get(fig, 'Position');
    panelWidth = 320;
    set(S.panel, 'Position', [0 0 panelWidth pos(4)]);
    set(S.ax,    'Position', [panelWidth 0 pos(3)-panelWidth pos(4)]);
end


%% ====================================================================
%   旋转地图（占位回调，步骤 E 实现）
%% ====================================================================
function onRotChanged(fig, src)
    % 步骤 E 实现
    deg = src.Value;
    if deg == 0, return; end
    setStatus(fig, sprintf('地图旋转功能将在步骤E实现 (当前 %g°)', deg));
end


%% ====================================================================
%   核心工具函数
%% ====================================================================
function out = getS(fig)
%GETS  读取全局状态
    out = getappdata(fig, 'S');
end

function setS(fig, S)
%SETS  写入全局状态
    setappdata(fig, 'S', S);
end

function setStatus(fig, msg)
%SETSTATUS  更新左下角状态栏
    try
        S = getS(fig);
        if isfield(S,'handles') && isfield(S.handles,'statusBar')
            sb = S.handles.statusBar;
            if isvalid(sb)
                sb.Text = ['当前: ' msg];
            end
        end
    catch
        % 静默忽略（batch 模式下 UI 控件可能受限）
    end
end

function refreshView(fig)
%REFRESHVIEW  把当前 mapDisplay 显示到 axes
    S = getS(fig);
    if isempty(S.mapDisplay), return; end
    imshow(S.mapDisplay, 'Parent', S.ax);
    axis(S.ax, 'image');
    % 固定坐标，方便后续 get(gca,'CurrentPoint') 取像素
    set(S.ax, 'XLim',[0.5 S.mapW+0.5], 'YLim',[0.5 S.mapH+0.5], ...
              'YDir','normal');
    % 注：YDir='normal' 让 row 向上，但 imshow 默认是 YDir='reverse'
    % 我们统一用 reverse，便于和图像矩阵对应
    set(S.ax, 'YDir','reverse');
end

function pt = getPointerOnAxes(fig, ax)
%GETPOINTERONAXES  返回鼠标在 axes 上的 [col, row]（连续值）
    pt = [];
    if ~isgraphics(ax), return; end
    cp = get(ax, 'CurrentPoint');
    if isempty(cp), return; end
    col = cp(1,1); row = cp(1,2);
    % 必须在图像范围内
    S = getS(fig);
    if col < 1 || col > S.mapW || row < 1 || row > S.mapH
        return;
    end
    pt = [col row];
end

function [wx, wy] = px2world(fig, col, row)
%PX2WORLD  像素坐标 -> 世界坐标（米）
%  现实原点 = 图像左下角；X 向右；Y 向上
    S = getS(fig);
    wx = col * S.scale;
    wy = (S.mapH - row) * S.scale;
end

function [col, row] = world2px(fig, wx, wy)
%WORLD2PX  世界坐标(米) -> 像素坐标
    S = getS(fig);
    col = wx / S.scale;
    row = S.mapH - wy / S.scale;
end


%% ====================================================================
%   骨架绘制
%% ====================================================================
function drawSkeleton(fig)
%DRAWSKELETON  在地图副本上手绘骨架（红色线段 + 黄色节点）
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    S.mapDisplay = S.mapOrigin;   % 从原图重新复制

    % —— 画线段（红色）——
    lineColor = uint8([255 0 0]);
    for i = 1:size(S.sk.edges, 1)
        ni = S.sk.edges(i,1); nj = S.sk.edges(i,2);
        A = S.sk.nodes(ni,:); B = S.sk.nodes(nj,:);
        pxs = bresenham(A(1), A(2), B(1), B(2));
        for k = 1:size(pxs,1)
            c = pxs(k,1); r = pxs(k,2);
            if c>=1 && c<=S.mapW && r>=1 && r<=S.mapH
                S.mapDisplay(r, c, :) = lineColor;
            end
        end
    end

    % —— 画节点（黄色 3x3 方块）——
    nodeColor = uint8([255 255 0]);
    for i = 1:size(S.sk.nodes, 1)
        c = round(S.sk.nodes(i,1)); r = round(S.sk.nodes(i,2));
        for dr = -1:1
            for dc = -1:1
                rr = r+dr; cc = c+dc;
                if cc>=1 && cc<=S.mapW && rr>=1 && rr<=S.mapH
                    S.mapDisplay(rr, cc, :) = nodeColor;
                end
            end
        end
    end

    setS(fig, S);
    refreshView(fig);
end


%% ====================================================================
%   几何 / 图形算法（手写）
%% ====================================================================
function d = ptToSegDist(P, A, B)
%PTTOSEGDIST  点 P 到线段 AB 的最短距离
    AB = B - A;
    AP = P - A;
    ab2 = dot(AB, AB);
    if ab2 == 0
        d = norm(P - A);
        return;
    end
    t = dot(AP, AB) / ab2;
    t = max(0, min(1, t));          % 钳制到 [0,1]，保证投影落在线段上
    closest = A + t * AB;
    d = norm(P - closest);
end

function pts = bresenham(x0, y0, x1, y1)
%BRESENHAM  经典 Bresenham 直线算法，返回线上所有像素 [col row]
    x0 = round(x0); y0 = round(y0); x1 = round(x1); y1 = round(y1);
    dx = abs(x1 - x0); dy = abs(y1 - y0);
    sx = sign(x1 - x0); sy = sign(y1 - y0);
    if sx == 0, sx = 1; end
    if sy == 0, sy = 1; end
    err = dx - dy;
    pts = zeros(0, 2);
    while true
        pts(end+1, :) = [x0, y0];   %#ok<AGROW>
        if x0 == x1 && y0 == y1, break; end
        e2 = 2 * err;
        if e2 > -dy
            err = err - dy;
            x0 = x0 + sx;
        end
        if e2 < dx
            err = err + dx;
            y0 = y0 + sy;
        end
    end
end
