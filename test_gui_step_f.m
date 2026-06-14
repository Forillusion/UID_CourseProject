%TEST_GUI_STEP_F  测量功能 GUI 集成测试
fprintf('========== GUI Step F Test ==========\n');
try
    fig = main();
    S = getappdata(fig, 'S');

    % 检查控件
    fn = fieldnames(S.handles);
    for n = {'btnMeasure2','btnTrack','btnClearMeasure','measureLabel'}
        assert(ismember(n{1}, fn), sprintf('%s missing', n{1}));
    end
    fprintf('[OK] measurement controls exist\n');

    % 测量模式设置
    S.handles.btnMeasure2.ButtonPushedFcn(S.handles.btnMeasure2, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.mode, 'measure2'), 'mode not measure2');
    fprintf('[OK] btnMeasure2 sets mode\n');

    S.handles.btnTrack.ButtonPushedFcn(S.handles.btnTrack, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.mode, 'track'), 'mode not track');
    fprintf('[OK] btnTrack sets mode\n');

    % 清除测量
    S.handles.btnClearMeasure.ButtonPushedFcn(S.handles.btnClearMeasure, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.mode, 'idle'), 'mode not idle after clear');
    assert(isempty(S.measurePts), 'measurePts not cleared');
    fprintf('[OK] btnClearMeasure works\n');

    % 测量标签更新
    assert(strcmp(S.handles.measureLabel.Text, '距离: ---'), 'label not reset');
    fprintf('[OK] measureLabel reset\n');

    delete(fig);
    fprintf('[OK] GUI Step F Test PASSED\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),4)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end
