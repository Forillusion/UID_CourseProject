%TEST_GUI_STEP_B  测试骨架绘制功能
fprintf('========== GUI Step B Test ==========\n');
try
    fig = main();
    S = getappdata(fig, 'S');
    assert(~isempty(S.mapOrigin), 'map not loaded');

    % 模拟手动添加骨架：3条折线
    S.sk.nodes = [100 100; 200 150; 300 100; 300 300; 450 300];
    S.sk.edges = [1 2; 2 3; 3 4; 4 5];
    S.sketchChain = [];
    setappdata(fig, 'S', S);

    % 调用 drawSkeleton（local function，通过模拟无法直接调）
    % 改为检查按钮是否存在
    fn = fieldnames(S.handles);
    assert(ismember('btnSketch', fn), 'btnSketch missing');
    assert(ismember('btnErase', fn), 'btnErase missing');
    assert(ismember('btnClearSkeleton', fn), 'btnClearSkeleton missing');
    assert(ismember('btnShowSkeleton', fn), 'btnShowSkeleton missing');
    fprintf('[OK] skeleton buttons exist\n');

    % 模拟点击 sketch 按钮
    S.handles.btnSketch.ButtonPushedFcn(S.handles.btnSketch, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.mode, 'sketch'), 'mode not sketch after btnSketch');
    fprintf('[OK] btnSketch sets mode=sketch\n');

    % 模拟点击 erase 按钮
    S.handles.btnErase.ButtonPushedFcn(S.handles.btnErase, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.mode, 'erase'), 'mode not erase after btnErase');
    fprintf('[OK] btnErase sets mode=erase\n');

    % 模拟点击 clear
    S = getappdata(fig, 'S');
    S.sk.nodes = [1 1; 2 2];  % ensure non-empty
    S.sk.edges = [1 2];
    setappdata(fig, 'S', S);
    S.handles.btnClearSkeleton.ButtonPushedFcn(S.handles.btnClearSkeleton, []);
    S = getappdata(fig, 'S');
    assert(isempty(S.sk.nodes), 'nodes not cleared');
    assert(isempty(S.sk.edges), 'edges not cleared');
    fprintf('[OK] btnClearSkeleton clears skeleton\n');

    delete(fig);
    fprintf('[OK] GUI Step B Test PASSED\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),4)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end
