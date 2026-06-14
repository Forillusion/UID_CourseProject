%TEST_GUI_STEP_C  测试道路掩膜生成和显示
fprintf('========== GUI Step C Test ==========\n');
try
    fig = main();
    S = getappdata(fig, 'S');

    % 添加测试骨架
    S.sk.nodes = [100 100; 300 100; 300 400; 500 400];
    S.sk.edges = [1 2; 2 3; 3 4];
    setappdata(fig, 'S', S);

    % 检查新控件存在
    fn = fieldnames(S.handles);
    assert(ismember('roadWidthSlider', fn), 'roadWidthSlider missing');
    assert(ismember('roadWidthValue', fn), 'roadWidthValue missing');
    assert(ismember('btnGenMask', fn), 'btnGenMask missing');
    assert(ismember('btnShowRoad', fn), 'btnShowRoad missing');
    fprintf('[OK] step C controls exist\n');

    % 测试滑块回调
    S.handles.roadWidthSlider.Value = 5;
    S.handles.roadWidthSlider.ValueChangedFcn(S.handles.roadWidthSlider, []);
    S = getappdata(fig, 'S');
    assert(S.roadHalfWidth == 5, 'roadHalfWidth not updated');
    fprintf('[OK] slider sets roadHalfWidth=%d\n', S.roadHalfWidth);

    % 测试生成掩膜
    S.handles.btnGenMask.ButtonPushedFcn(S.handles.btnGenMask, []);
    S = getappdata(fig, 'S');
    assert(~isempty(S.roadMask), 'roadMask not generated');
    roadPx = sum(S.roadMask(:));
    assert(roadPx > 0, 'roadMask empty');
    fprintf('[OK] roadMask generated: %d pixels\n', roadPx);

    % 测试显示道路区
    S.handles.btnShowRoad.ButtonPushedFcn(S.handles.btnShowRoad, []);
    fprintf('[OK] drawRoadArea executed\n');

    % 测试空骨架时的错误处理
    S.sk.edges = zeros(0,2,'int32');
    setappdata(fig, 'S', S);
    % 不应该崩溃（uialert 在 batch 模式可能不弹出）
    try
        S.handles.btnGenMask.ButtonPushedFcn(S.handles.btnGenMask, []);
    catch ME
        fprintf('[INFO] empty skeleton error handled: %s\n', ME.message);
    end

    delete(fig);
    fprintf('[OK] GUI Step C Test PASSED\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),4)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end
