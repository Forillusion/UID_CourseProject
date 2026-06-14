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
    rows = 22;
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
    addC('label', r, 'Text','提示: sketch模式 左键画点/右键结束折线', 'FontSize',8, 'FontAngle','italic');

    % ----- 智能车分组（占位） -----
    r = r + 1;
    addC('label', r, 'Text','──── 智能车 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    addC('label', r, 'Text','(步骤D 实现)', 'FontSize',8, 'FontAngle','italic');

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
