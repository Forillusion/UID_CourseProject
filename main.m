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
    S.sketchState = 'idle';  % 骨架工作流: idle/sketching/erasing/finalized
    S.rotDeg    = 0;         % 当前地图旋转角度
    S.rotSize   = [];        % 旋转后画布尺寸 [newH newW]（空=未旋转）
    S.dispH     = S.mapH;    % 当前显示图高度（行）
    S.dispW     = S.mapW;    % 当前显示图宽度（列）

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

    % —— 函数句柄（供 or1_skeleton.m 跨文件调用） ——
    S.fn = struct();
    S.fn.refresh = @refreshDisplay;
    S.fn.setStatus = @setStatus;
    S.fn.updateDropdown = @updateIVDropdown;

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
    h.rotLabel = addC('label', r, 'Text','(有bug)旋转角度 (度): 0');
    r = r + 1;
    h.rotSlider = addC('slider', r, 'Value',0, 'Limits',[-180 180], ...
                       'MajorTicks',[-180 -90 0 90 180], ...
                       'ValueChangedFcn', @(s,e) onRotChanged(fig,s));

    % ----- 道路骨架 (OR1) -----
    r = r + 1;
    addC('label', r, 'Text','──── 道路骨架 (OR1) ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.btnOR1 = addC('button', r, 'Text','打开骨架工具', ...
                    'ButtonPushedFcn', @(s,e) or1_skeleton('open', fig));
    r = r + 1;
    addC('label', r, 'Text','点击打开独立窗口提取道路骨架', 'FontSize',8, 'FontAngle','italic');

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

    % ----- 测量分组 -----
    r = r + 1;
    addC('label', r, 'Text','──── 测量 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.btnMeasure2 = addC('button', r, 'Text','两点测距', ...
                         'ButtonPushedFcn', @(s,e) onBtnMeasure2(fig));
    r = r + 1;
    h.btnTrack = addC('button', r, 'Text','轨迹测量', ...
                      'ButtonPushedFcn', @(s,e) onBtnTrack(fig));
    r = r + 1;
    h.btnClearMeasure = addC('button', r, 'Text','清除测量标记', ...
                             'ButtonPushedFcn', @(s,e) onBtnClearMeasure(fig));
    r = r + 1;
    h.measureLabel = addC('label', r, 'Text','距离: ---', 'FontSize',9, 'FontWeight','bold');

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
        case {'sketch', 'erase'}
            or1_skeleton('click', fig, col, row, selType);
        case 'loadIV'
            handleLoadIVClick(fig, col, row);
        case 'measure2'
            handleMeasure2Click(fig, col, row);
        case 'track'
            handleTrackClick(fig, col, row);
        otherwise
            % idle：仅显示坐标，已在上面处理
    end
end

function onMouseUp(fig, ~)
    % 预留：拖拽相关
end

function map = overlaySkeleton(map, nodes, edges, mapW, mapH)
%OVERLAYSKELETON  在地图矩阵上叠加骨架（粗实红线 + 黄色节点），纯函数无副作用
    [H, W, ~] = size(map);
    lineColor = uint8([255 0 0]);   % 红色实线
    nodeColor = uint8([255 255 0]); % 黄色节点
    lineR = 1;   % 线半宽=1 -> 3px 粗实线（避免对角线断裂成虚线）
    nodeR = 2;
    for i = 1:size(edges, 1)
        ni = edges(i,1); nj = edges(i,2);
        A = nodes(ni,:); B = nodes(nj,:);
        pxs = bresenham(A(1), A(2), B(1), B(2));
        for k = 1:size(pxs,1)
            map = stampSquare(map, pxs(k,1), pxs(k,2), lineR, lineColor, W, H);
        end
    end
    for i = 1:size(nodes, 1)
        map = stampSquare(map, nodes(i,1), nodes(i,2), nodeR, nodeColor, W, H);
    end
end

function map = stampSquare(map, cx, cy, radius, color, W, H)
%STAMPSQUARE  在 (cx,cy) 处盖一个 (2*radius+1) 的实心方块
    cc0 = round(cx); rr0 = round(cy);
    for dr = -radius:radius
        for dc = -radius:radius
            rr = rr0 + dr; cc = cc0 + dc;
            if cc>=1 && cc<=W && rr>=1 && rr<=H
                map(rr, cc, :) = color;
            end
        end
    end
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
    refreshDisplay(fig);
    updateIVDropdown(fig);
    [wx, wy] = px2world(fig, col, row);
    setStatus(fig, sprintf('车辆 #%d 已加载 @ (%.1f, %.1f)m，朝向 %.0f°', ...
              v.id, wx, wy, v.angle));
end

function map = buildBaseMap(fig)
    S = getS(fig); map = S.mapOrigin;
    if isempty(map), return; end
    switch S.sketchState
        case {'sketching','erasing'}
            if ~isempty(S.sk.edges)
                map = overlaySkeleton(map, S.sk.nodes, S.sk.edges, S.mapW, S.mapH);
            end
        case 'finalized'
            if ~isempty(S.roadMask), map = overlayBlueRoad(map, S.roadMask); end
    end
    for i = 1:numel(S.vehicles)
        map = drawIV(map, S.vehicles(i).cx, S.vehicles(i).cy, ...
            S.vehicles(i).angle, S.vehicles(i).dispScale, S.mapW, S.mapH, S.scale);
    end
end

function map = overlayBlueRoad(map, roadMask)
    m = roadMask;
    R = double(map(:,:,1)); G = double(map(:,:,2)); B = double(map(:,:,3));
    R(m) = R(m)*0.5+15; G(m) = G(m)*0.5+50; B(m) = B(m)*0.5+110;
    map = uint8(cat(3,R,G,B));
end

function refreshDisplay(fig)
    S = getS(fig); if isempty(S.mapOrigin), return; end
    map = buildBaseMap(fig);
    if S.rotDeg ~= 0
        S = getS(fig); S.mapDisplay = rotateMap(map, S.rotDeg);
        S.rotSize = [size(S.mapDisplay,1), size(S.mapDisplay,2)];
    else
        S.mapDisplay = map; S.rotSize = [];
    end
    setS(fig, S); refreshView(fig);
end

function mapOut = drawIV(mapIn, cx, cy, angleDeg, dispScale, mapW, mapH, scale)
%DRAWIV  手搓绘制单辆 IV（旋转矩形）到地图矩阵上
%  真实 IV: 8m x 3m -> 像素 8/1.7 x 3/1.7 ≈ 4.7 x 1.8 -> x dispScale
%  车身为绿色，车头前段为黄色（与车身同宽）
    L = (8 / scale) * dispScale;   % 长（像素）
    Wd = (3 / scale) * dispScale;  % 宽（像素）
    headLen = L * 0.25;            % 车头长度（占全长 1/4）
    bodyLen = L - headLen;         % 车身长度
    th = deg2rad(angleDeg);
    R = [cos(th) -sin(th); sin(th) cos(th)];

    % —— 1. 画车身（绿色）：从中心偏后 headLen/2 开始 ——
    bodyCorners = [-(bodyLen/2 + headLen/2) -Wd/2; ...
                    (headLen - (bodyLen/2 + headLen/2)) -Wd/2; ...
                    (headLen - (bodyLen/2 + headLen/2))  Wd/2; ...
                   -(bodyLen/2 + headLen/2)  Wd/2];
    % 简化：车身后端 x = -L/2，前端 x = -L/2 + bodyLen = headLen - L/2
    bodyCorners = [-L/2 -Wd/2; headLen-L/2 -Wd/2; headLen-L/2 Wd/2; -L/2 Wd/2];
    bodyPts = bodyCorners * R' + [cx, cy];
    mapOut = mapIn;
    bodyColor = uint8([0 200 0]);   % 绿色车身
    [cMin, cMax, rMin, rMax] = polyBBox(bodyPts, mapW, mapH);
    for r = rMin:rMax
        for c = cMin:cMax
            if pointInPolygon([c, r], bodyPts)
                mapOut(r, c, :) = bodyColor;
            end
        end
    end

    % —— 2. 画车头（黄色）：前端段，与车身同宽 ——
    headCorners = [headLen-L/2 -Wd/2; L/2 -Wd/2; L/2 Wd/2; headLen-L/2 Wd/2];
    headPts = headCorners * R' + [cx, cy];
    headColor = uint8([255 255 0]); % 黄色车头
    [cMin, cMax, rMin, rMax] = polyBBox(headPts, mapW, mapH);
    for r = rMin:rMax
        for c = cMin:cMax
            if pointInPolygon([c, r], headPts)
                mapOut(r, c, :) = headColor;
            end
        end
    end
end

function [cMin, cMax, rMin, rMax] = polyBBox(ptsPx, mapW, mapH)
%POLYBBOX  计算多边形的像素 bounding box（钳制到地图范围）
    cMin = max(1, floor(min(ptsPx(:,1))));
    cMax = min(mapW, ceil(max(ptsPx(:,1))));
    rMin = max(1, floor(min(ptsPx(:,2))));
    rMax = min(mapH, ceil(max(ptsPx(:,2))));
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
    refreshDisplay(fig);
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
                refreshDisplay(fig);
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

%% ====================================================================
%   测量功能（步骤 F）
%% ====================================================================
function onBtnMeasure2(fig)
    S = getS(fig);
    S.mode = 'measure2';
    S.measurePts = zeros(0,2);
    setS(fig, S);
    setStatus(fig, '两点测距：请点击第一个点。');
    S.handles.measureLabel.Text = '距离: ---';
end

function onBtnTrack(fig)
    S = getS(fig);
    S.mode = 'track';
    S.measurePts = zeros(0,2);
    setS(fig, S);
    setStatus(fig, '轨迹测量：连续点击多个点，右键结束并显示总长度。');
    S.handles.measureLabel.Text = '长度: 0.00 m';
end

function onBtnClearMeasure(fig)
    S = getS(fig);
    S.mode = 'idle';
    S.measurePts = zeros(0,2);
    setS(fig, S);
    refreshDisplay(fig);   % 恢复到不含测量标记的视图
    setStatus(fig, '测量标记已清除。');
    S.handles.measureLabel.Text = '距离: ---';
end

function handleMeasure2Click(fig, col, row)
    S = getS(fig);
    S.measurePts(end+1, :) = [col, row];   %#ok<AGROW>
    nPts = size(S.measurePts, 1);
    if nPts == 1
        setS(fig, S);
        drawMeasurement(fig);
        setStatus(fig, '已选第一点，请点击第二个点。');
    elseif nPts == 2
        setS(fig, S);
        drawMeasurement(fig);
        d = norm(S.measurePts(2,:) - S.measurePts(1,:)) * S.scale;
        S.handles.measureLabel.Text = sprintf('距离: %.2f m', d);
        S.mode = 'idle';
        setS(fig, S);
        setStatus(fig, sprintf('两点距离: %.2f m', d));
    end
end

function handleTrackClick(fig, col, row)
    S = getS(fig);
    selType = get(fig, 'SelectionType');
    if strcmp(selType, 'alt')   % 右键结束
        S.mode = 'idle';
        setS(fig, S);
        totalLen = computeTrackLength(S.measurePts, S.scale);
        S.handles.measureLabel.Text = sprintf('长度: %.2f m', totalLen);
        setStatus(fig, sprintf('轨迹完成: %d 点, 总长 %.2f m', ...
                  size(S.measurePts,1), totalLen));
        return;
    end
    % 左键追加
    S.measurePts(end+1, :) = [col, row];   %#ok<AGROW>
    setS(fig, S);
    drawMeasurement(fig);
    totalLen = computeTrackLength(S.measurePts, S.scale);
    S.handles.measureLabel.Text = sprintf('长度: %.2f m', totalLen);
    setStatus(fig, sprintf('轨迹第 %d 点, 当前总长 %.2f m（右键结束）', ...
              size(S.measurePts,1), totalLen));
end

function len = computeTrackLength(pts, scale)
%COMPUTETRACKLENGTH  计算折线总长度（米）
    len = 0;
    for i = 2:size(pts,1)
        len = len + norm(pts(i,:) - pts(i-1,:)) * scale;
    end
end

function drawMeasurement(fig)
%DRAWMEASUREMENT  在地图上绘制测量点+连线（青色），叠加在复合图上并应用旋转
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    % 1. 先构建复合图（原图+骨架+车辆）
    map = buildBaseMap(fig);
    [H, W, ~] = size(map);
    % 2. 叠加测量标记（青色连线 + 品红节点）
    pts = S.measurePts;
    if size(pts,1) >= 2
        for i = 2:size(pts,1)
            pxs = bresenham(pts(i-1,1), pts(i-1,2), pts(i,1), pts(i,2));
            for k = 1:size(pxs,1)
                map = stampSquare(map, pxs(k,1), pxs(k,2), 1, uint8([0 220 220]), W, H);
            end
        end
    end
    for i = 1:size(pts,1)
        map = stampSquare(map, pts(i,1), pts(i,2), 2, uint8([220 0 220]), W, H);
    end
    % 3. 应用旋转
    if S.rotDeg ~= 0
        S.mapDisplay = rotateMap(map, S.rotDeg);
        S.rotSize = [size(S.mapDisplay,1), size(S.mapDisplay,2)];
    else
        S.mapDisplay = map;
        S.rotSize = [];
    end
    setS(fig, S);
    refreshView(fig);
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
%ONROTCHANGED  地图旋转回调（滑条）；对完整叠加图(地图+骨架+车辆)做手搓反向映射旋转
    deg = round(src.Value);
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    % 同步滑条与标签
    src.Value = deg;
    if isfield(S.handles,'rotLabel') && isvalid(S.handles.rotLabel)
        S.handles.rotLabel.Text = sprintf('(有bug)旋转角度 (度): %.0f', deg);
    end
    S.rotDeg = deg;
    setS(fig, S);
    % drawAllVehicles 会构建复合图并按 rotDeg 旋转（保证骨架/车辆一起转、不丢失）
    refreshDisplay(fig);
    setStatus(fig, sprintf('地图已旋转 %.0f°（手搓反向映射）。', deg));
end

function out = rotateMap(img, deg)
%ROTATEMAP  手搓图像旋转（反向映射 + 最近邻采样）
%  对输出图每个像素，反向映射回原图取最近邻像素值。
    [H, W, ~] = size(img);
    th = deg2rad(deg);
    c = cos(th); s = sin(th);

    % 1. 计算旋转后新画布的外接尺寸
    corners = [0 0; W 0; W H; 0 H];
    rotCorners = corners * [c -s; s c]';
    newW = ceil(max(rotCorners(:,1)) - min(rotCorners(:,1)));
    newH = ceil(max(rotCorners(:,2)) - min(rotCorners(:,2)));
    out = uint8(zeros(newH, newW, 3));

    % 2. 新旧画布中心
    cxOld = W/2; cyOld = H/2;
    cxNew = newW/2; cyNew = newH/2;

    % 3. 向量化反向映射（避免慢速双重循环）
    [rr, cc] = meshgrid(1:newW, 1:newH);  % rr=行(y), cc=列(x)
    x = cc(:) - cxNew;          % 相对新中心
    y = rr(:) - cyNew;
    % 反向旋转（用 -th）：将新图坐标映射回原图坐标
    xOld =  x*c + y*s + cxOld;
    yOld = -x*s + y*c + cyOld;
    rOld = round(yOld);
    cOld = round(xOld);
    % 4. 有效区域掩膜
    valid = rOld>=1 & rOld<=H & cOld>=1 & cOld<=W;
    idx = find(valid);
    out(idx) = img(rOld(idx) + (cOld(idx)-1)*H);   % 线性索引（列优先）
    % RGB 三通道一起赋值（上面的线性索引对 3D 自动广播）
    for ch = 1:3
        tmp = out(:,:,ch);
        tmp2 = img(:,:,ch);
        tmp(idx) = tmp2(rOld(idx) + (cOld(idx)-1)*H);
        out(:,:,ch) = tmp;
    end
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
%REFRESHVIEW  把当前 mapDisplay 显示到 axes（按旋转后尺寸设定坐标范围）
    S = getS(fig);
    if isempty(S.mapDisplay), return; end
    [dH, dW, ~] = size(S.mapDisplay);
    imshow(S.mapDisplay, 'Parent', S.ax);
    axis(S.ax, 'image');
    % 按【显示图】尺寸设定坐标范围，保证旋转后大图不被裁切
    set(S.ax, 'XLim',[0.5 dW+0.5], 'YLim',[0.5 dH+0.5], ...
              'YDir','reverse');
    % 记录显示尺寸，供 getPointerOnAxes 做边界判定与反旋转
    S = getS(fig);
    S.dispH = dH; S.dispW = dW;
    setS(fig, S);
end

function pt = getPointerOnAxes(fig, ax)
%GETPOINTERONAXES  返回鼠标在【原始地图】坐标系下的 [col, row]
%  若当前处于旋转态，先把鼠标点(显示坐标)反旋转回原图坐标，保证下游逻辑一致。
    pt = [];
    if ~isgraphics(ax), return; end
    cp = get(ax, 'CurrentPoint');
    if isempty(cp), return; end
    colD = cp(1,1); rowD = cp(1,2);   % 显示图中的列/行
    S = getS(fig);
    % 边界判定用显示图尺寸
    if colD < 1 || colD > S.dispW || rowD < 1 || rowD > S.dispH
        return;
    end
    if S.rotDeg ~= 0 && ~isempty(S.rotSize)
        % 反旋转：显示坐标 -> 原图坐标
        th = deg2rad(S.rotDeg);
        c = cos(th); s = sin(th);
        newH = S.rotSize(1); newW = S.rotSize(2);
        x = colD - newW/2;          % 相对新(显示)中心
        y = rowD - newH/2;
        colO =  x*c + y*s + S.mapW/2;   % 反向旋转(-th)回原图
        rowO = -x*s + y*c + S.mapH/2;
        col = colO; row = rowO;
        % 必须落在原图范围内（旋转后的黑边区域视为无效）
        if col < 1 || col > S.mapW || row < 1 || row > S.mapH
            return;
        end
    else
        col = colD; row = rowD;
        if col < 1 || col > S.mapW || row < 1 || row > S.mapH
            return;
        end
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
%   几何 / 图形算法（手写）
%   ptToSegDist / genRoadMask 已迁移到 or1_skeleton.m
%% ====================================================================
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
