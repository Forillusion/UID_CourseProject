function or1_skeleton(action, mainFig, varargin)
%OR1_SKELETON  OR1 道路骨架工具（弹出窗口）
%  用法：
%    or1_skeleton('open', mainFig)                         打开弹窗
%    or1_skeleton('click', mainFig, col, row, selType)     主窗口鼠标点击分发
%    or1_skeleton('close', mainFig)                        弹窗关闭处理
%
%  弹窗只有控制按钮（无地图），操作直接作用于主窗口地图。
%  关闭弹窗时若正在编辑(sketching/erasing)，自动完成提取(finalized)。

    switch action
        case 'open'
            do_open(mainFig);
        case 'click'
            do_click(mainFig, varargin{:});
        case 'close'
            do_close(mainFig);
    end
end


%% ====================================================================
%   打开弹窗
%% ====================================================================
function do_open(mainFig)
    S = getappdata(mainFig, 'S');

    % 若弹窗已存在，前置并返回
    if isfield(S, 'or1Fig') && ~isempty(S.or1Fig) && isvalid(S.or1Fig)
        figure(S.or1Fig);
        return;
    end

    or1Fig = uifigure('Name', '道路骨架工具 (OR1)', ...
                      'Position', [150 150 280 480], ...
                      'Resize', 'off');
    setappdata(or1Fig, 'mainFig', mainFig);

    gl = uigridlayout(or1Fig, [18 1]);
    gl.RowHeight = repmat({'fit'}, 18, 1);
    gl.ColumnWidth = {'1x'};

    r = 0;
    % 辅助函数
    function c = addC(type, rowIdx, varargin)
        c = feval(['ui' type], gl, varargin{:});
        c.Layout.Row = rowIdx; c.Layout.Column = 1;
    end

    % ----- 标题 -----
    r = r + 1;
    addC('label', r, 'Text', '道路骨架工具 (OR1)', ...
         'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    % ----- 操作按钮 -----
    r = r + 1;
    addC('label', r, 'Text', '──── 操作 ────', 'FontSize', 11, 'FontWeight', 'bold');
    r = r + 1;
    btnSketch = addC('button', r, 'Text', '提取骨架', ...
        'ButtonPushedFcn', @(~,~) onBtnSketch(or1Fig));
    r = r + 1;
    btnFinish = addC('button', r, 'Text', '提取结束', 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onBtnFinish(or1Fig));
    r = r + 1;
    btnErase = addC('button', r, 'Text', '擦除道路', 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onBtnErase(or1Fig));
    r = r + 1;
    btnClear = addC('button', r, 'Text', '清空道路', ...
        'ButtonPushedFcn', @(~,~) onBtnClear(or1Fig));

    % ----- 道路宽度 -----
    r = r + 1;
    addC('label', r, 'Text', '道路半宽(像素):', 'FontSize', 9);
    r = r + 1;
    widthSlider = addC('slider', r, 'Value', S.roadHalfWidth, 'Limits', [1 15], ...
        'MajorTicks', [1 5 10 15], ...
        'ValueChangedFcn', @(src,~) onWidthChanged(or1Fig, src));
    r = r + 1;
    widthValue = addC('label', r, 'Text', sprintf('当前: %d 像素', S.roadHalfWidth), 'FontSize', 9);

    % ----- 模式标签 -----
    r = r + 1;
    modeLabel = addC('label', r, 'Text', '当前模式: 空闲', ...
        'FontSize', 11, 'FontWeight', 'bold', 'FontColor', [0 0.5 0]);

    % ----- 提示 -----
    r = r + 1;
    addC('label', r, 'Text', '左键画点 右键结束折线', 'FontSize', 8, 'FontAngle', 'italic');
    r = r + 1;
    addC('label', r, 'Text', '擦除:点击线段整条删除', 'FontSize', 8, 'FontAngle', 'italic');

    % ----- 统计 -----
    r = r + 1;
    statLabel = addC('label', r, 'Text', '节点: 0  线段: 0', 'FontSize', 9);

    % ----- 关闭 -----
    r = r + 1;
    addC('button', r, 'Text', '关闭并返回主窗口', ...
        'ButtonPushedFcn', @(~,~) close(or1Fig));

    % 存储 OR1 控件句柄
    S.or1Fig = or1Fig;
    S.or1 = struct();
    S.or1.btnSketch  = btnSketch;
    S.or1.btnFinish  = btnFinish;
    S.or1.btnErase   = btnErase;
    S.or1.btnClear   = btnClear;
    S.or1.widthSlider = widthSlider;
    S.or1.widthValue  = widthValue;
    S.or1.modeLabel   = modeLabel;
    S.or1.statLabel   = statLabel;
    setappdata(mainFig, 'S', S);

    % 关闭回调
    set(or1Fig, 'CloseRequestFcn', @(~,~) or1_skeleton('close', mainFig));

    % 初始化按钮状态
    or1_setState(mainFig, S.sketchState);
end


%% ====================================================================
%   关闭弹窗（自动完成提取）
%% ====================================================================
function do_close(mainFig)
    S = getappdata(mainFig, 'S');
    % 若正在编辑，自动完成
    if strcmp(S.sketchState, 'sketching') || strcmp(S.sketchState, 'erasing')
        if ~isempty(S.sk.edges)
            S.roadMask = genRoadMask(S.sk.nodes, S.sk.edges, S.roadHalfWidth, S.mapW, S.mapH);
            S.sketchState = 'finalized';
        else
            S.sketchState = 'idle';
        end
    end
    S.mode = 'idle';
    % 删除弹窗
    if isfield(S, 'or1Fig') && isvalid(S.or1Fig)
        delete(S.or1Fig);
    end
    S.or1Fig = [];
    S = rmfield(S, 'or1'); %#ok<RMFELD>
    setappdata(mainFig, 'S', S);
    % 刷新主窗口
    S.fn.refresh(mainFig);
    S.fn.setStatus(mainFig, sprintf('骨架工具已关闭。状态: %s', S.sketchState));
end


%% ====================================================================
%   鼠标点击分发（由主窗口 onMouseDown 调用）
%% ====================================================================
function do_click(mainFig, col, row, selType)
    S = getappdata(mainFig, 'S');
    if strcmp(S.mode, 'sketch')
        if strcmp(selType, 'alt')
            S.sketchChain = [];
            setappdata(mainFig, 'S', S);
            S.fn.setStatus(mainFig, '折线已结束，可开始新的折线。');
        else
            do_sketch_click(mainFig, col, row);
        end
    elseif strcmp(S.mode, 'erase')
        do_erase_click(mainFig, col, row);
    end
end

function do_sketch_click(mainFig, col, row)
    S = getappdata(mainFig, 'S');
    S.sk.nodes(end+1, :) = [col, row];   %#ok<AGROW>
    nodeIdx = size(S.sk.nodes, 1);
    if ~isempty(S.sketchChain)
        prev = S.sketchChain(end);
        S.sk.edges(end+1, :) = [prev, nodeIdx];  %#ok<AGROW>
    end
    S.sketchChain(end+1) = nodeIdx;      %#ok<AGROW>
    setappdata(mainFig, 'S', S);
    S.fn.refresh(mainFig);
    or1_updateStat(mainFig);
    S.fn.setStatus(mainFig, sprintf('已添加节点 #%d（折线内第 %d 点）', nodeIdx, numel(S.sketchChain)));
end

function do_erase_click(mainFig, col, row)
    S = getappdata(mainFig, 'S');
    if isempty(S.sk.edges)
        S.fn.setStatus(mainFig, '无骨架可擦除。');
        return;
    end
    P = [col, row];
    threshold = 6;
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
        ni_old = S.sk.edges(bestIdx, 1); nj_old = S.sk.edges(bestIdx, 2);
        A_old = S.sk.nodes(ni_old, :); B_old = S.sk.nodes(nj_old, :);
        S.sk.edges(bestIdx, :) = [];
        S = cleanupNodes(S);
        S = removeVehiclesOnEdge(S, A_old, B_old);
        setappdata(mainFig, 'S', S);
        S.fn.refresh(mainFig);
        or1_updateStat(mainFig);
        S.fn.updateDropdown(mainFig);
        S.fn.setStatus(mainFig, sprintf('已擦除线段（距离 %.1f 像素）', bestDist));
    else
        S.fn.setStatus(mainFig, sprintf('未命中线段（最近 %.1f 像素）', bestDist));
    end
end


%% ====================================================================
%   按钮回调
%% ====================================================================
function onBtnSketch(or1Fig)
    mainFig = getappdata(or1Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.sketchChain = [];
    setappdata(mainFig, 'S', S);
    or1_setState(mainFig, 'sketching');
    S.fn.refresh(mainFig);
    S.fn.setStatus(mainFig, '点选输入：左键画点，右键结束当前折线。');
end

function onBtnFinish(or1Fig)
    mainFig = getappdata(or1Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    if isempty(S.sk.edges)
        uialert(or1Fig, '尚未画出任何道路骨架。', '提示');
        return;
    end
    S.fn.setStatus(mainFig, sprintf('正在生成道路掩膜（半宽=%d像素）...', S.roadHalfWidth));
    drawnow;
    S.roadMask = genRoadMask(S.sk.nodes, S.sk.edges, S.roadHalfWidth, S.mapW, S.mapH);
    setappdata(mainFig, 'S', S);
    roadPx = sum(S.roadMask(:));
    or1_setState(mainFig, 'finalized');
    S.fn.setStatus(mainFig, sprintf('提取完成！道路掩膜 %d 像素。', roadPx));
end

function onBtnErase(or1Fig)
    mainFig = getappdata(or1Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    if strcmp(S.sketchState, 'erasing')
        or1_setState(mainFig, 'sketching');
        S.fn.setStatus(mainFig, '已返回点选输入模式。');
    else
        if isempty(S.sk.edges)
            uialert(or1Fig, '尚无线段可擦除。', '提示');
            return;
        end
        or1_setState(mainFig, 'erasing');
        S.fn.setStatus(mainFig, '擦除模式：点击要删除的线段。');
    end
end

function onBtnClear(or1Fig)
    mainFig = getappdata(or1Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.sk.nodes = zeros(0, 2);
    S.sk.edges = zeros(0, 2, 'int32');
    S.sketchChain = [];
    S.roadMask = [];
    S.vehicles = struct('id', {}, 'cx', {}, 'cy', {}, 'angle', {}, 'dispScale', {});
    setappdata(mainFig, 'S', S);
    or1_setState(mainFig, 'idle');
    S.fn.refresh(mainFig);
    or1_updateStat(mainFig);
    S.fn.updateDropdown(mainFig);
    S.fn.setStatus(mainFig, '道路已全部清空，车辆已移除。');
end

function onWidthChanged(or1Fig, src)
    mainFig = getappdata(or1Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.roadHalfWidth = round(src.Value);
    S.or1.widthValue.Text = sprintf('当前: %d 像素', S.roadHalfWidth);
    if strcmp(S.sketchState, 'finalized') && ~isempty(S.sk.edges)
        S.roadMask = genRoadMask(S.sk.nodes, S.sk.edges, S.roadHalfWidth, S.mapW, S.mapH);
    end
    setappdata(mainFig, 'S', S);
    S.fn.refresh(mainFig);
end


%% ====================================================================
%   状态机
%% ====================================================================
function or1_setState(mainFig, newState)
    S = getappdata(mainFig, 'S');
    S.sketchState = newState;
    switch newState
        case 'sketching', S.mode = 'sketch';
        case 'erasing',   S.mode = 'erase';
        otherwise,        S.mode = 'idle';
    end
    setappdata(mainFig, 'S', S);
    % 更新弹窗按钮
    h = S.or1;
    switch newState
        case {'idle', 'finalized'}
            h.btnSketch.Enable = 'on';
            h.btnFinish.Enable = 'off';
            h.btnErase.Enable = 'off';
            h.btnErase.Text = '擦除道路';
        case 'sketching'
            h.btnSketch.Enable = 'on';
            h.btnFinish.Enable = 'on';
            h.btnErase.Enable = 'on';
            h.btnErase.Text = '擦除道路';
        case 'erasing'
            h.btnSketch.Enable = 'on';
            h.btnFinish.Enable = 'on';
            h.btnErase.Enable = 'on';
            h.btnErase.Text = '返回点选';
    end
    % 更新模式标签
    lbl = h.modeLabel;
    switch newState
        case 'idle'
            lbl.Text = '当前模式: 空闲'; lbl.FontColor = [0 0.5 0];
        case 'sketching'
            lbl.Text = '当前模式: 点选输入'; lbl.FontColor = [0.8 0 0];
        case 'erasing'
            lbl.Text = '当前模式: 擦除'; lbl.FontColor = [0.5 0 0.5];
        case 'finalized'
            lbl.Text = '当前模式: 提取完成'; lbl.FontColor = [0 0 0.8];
    end
    or1_updateStat(mainFig);
    % 光标
    if strcmp(newState, 'erasing')
        set(mainFig, 'Pointer', 'circle');
    else
        set(mainFig, 'Pointer', 'arrow');
    end
end

function or1_updateStat(mainFig)
    S = getappdata(mainFig, 'S');
    if isfield(S, 'or1') && isfield(S.or1, 'statLabel')
        nN = size(S.sk.nodes, 1);
        nE = size(S.sk.edges, 1);
        S.or1.statLabel.Text = sprintf('节点: %d  线段: %d', nN, nE);
    end
end


%% ====================================================================
%   算法（从 main.m 迁移）
%% ====================================================================
function mask = genRoadMask(nodes, edges, halfWidth, mapW, mapH)
    mask = false(mapH, mapW);
    tol = halfWidth + 1;
    for i = 1:size(edges, 1)
        ni = edges(i, 1); nj = edges(i, 2);
        A = nodes(ni, :); B = nodes(nj, :);
        cMin = max(1, floor(min(A(1), B(1)) - tol));
        cMax = min(mapW, ceil(max(A(1), B(1)) + tol));
        rMin = max(1, floor(min(A(2), B(2)) - tol));
        rMax = min(mapH, ceil(max(A(2), B(2)) + tol));
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

function S = cleanupNodes(S)
    nNodes = size(S.sk.nodes, 1);
    if nNodes == 0, return; end
    used = false(nNodes, 1);
    if ~isempty(S.sk.edges)
        used(S.sk.edges(:)) = true;
    end
    keepIdx = find(used);
    newMap = zeros(nNodes, 1);
    newMap(keepIdx) = 1:numel(keepIdx);
    if ~isempty(S.sk.edges)
        S.sk.edges(:, 1) = newMap(S.sk.edges(:, 1));
        S.sk.edges(:, 2) = newMap(S.sk.edges(:, 2));
    end
    S.sk.nodes = S.sk.nodes(keepIdx, :);
end

function S = removeVehiclesOnEdge(S, A, B)
    if isempty(S.vehicles), return; end
    keep = true(numel(S.vehicles), 1);
    for i = 1:numel(S.vehicles)
        d = ptToSegDist([S.vehicles(i).cx, S.vehicles(i).cy], A, B);
        if d <= S.roadHalfWidth
            keep(i) = false;
        end
    end
    if ~all(keep)
        S.vehicles = S.vehicles(keep);
    end
end

function d = ptToSegDist(P, A, B)
    AB = B - A;
    AP = P - A;
    ab2 = dot(AB, AB);
    if ab2 == 0
        d = norm(P - A);
        return;
    end
    t = dot(AP, AB) / ab2;
    t = max(0, min(1, t));
    closest = A + t * AB;
    d = norm(P - closest);
end
