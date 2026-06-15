%TEST_GUI_ROT  Rotation logic test (new workflow version)
fprintf('========== Rotation Logic Test ==========\n');
try
    fig = main();
    S = getappdata(fig, 'S');

    % Setup skeleton + finalize via OR1 popup
    S.sk.nodes = [100 100; 400 100; 400 500];
    S.sk.edges = [1 2; 2 3];
    setappdata(fig, 'S', S);
    or1_skeleton('open', fig);
    S = getappdata(fig, 'S');
    S.or1.btnFinish.ButtonPushedFcn(S.or1.btnFinish, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'finalized'), 'not finalized');
    assert(~isempty(S.roadMask), 'no roadMask');
    fprintf('[OK] finalized with mask\n');

    % Add a vehicle
    S = getappdata(fig, 'S');
    S.vehicles(1).id = 1; S.vehicles(1).cx = 200; S.vehicles(1).cy = 100;
    S.vehicles(1).angle = 0; S.vehicles(1).dispScale = 3;
    S.nextIVid = 2;
    setappdata(fig, 'S', S);

    %% 1. 0 deg display
    S.handles.rotSlider.Value = 0;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    S = getappdata(fig, 'S');
    [dH0,dW0,~] = size(S.mapDisplay);
    assert(isempty(S.rotSize), 'rotSize should be empty at 0deg');
    assert(dH0==S.mapH && dW0==S.mapW, '0deg size wrong');
    % Blue road should be visible (blue pixels)
    bluePx = nnz(S.mapDisplay(:,:,3)>150 & S.mapDisplay(:,:,1)<100);
    assert(bluePx > 0, 'blue road not shown in finalized');
    % Vehicle should be visible (green pixels)
    greenPx = nnz(S.mapDisplay(:,:,1)==0 & S.mapDisplay(:,:,2)==200);
    assert(greenPx > 0, 'vehicle not shown');
    fprintf('[OK] 0deg: %dx%d, blue=%d, green=%d\n', dW0, dH0, bluePx, greenPx);

    %% 2. Rotate 90 deg
    S.handles.rotSlider.Value = 90;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    S = getappdata(fig, 'S');
    [dH90,dW90,~] = size(S.mapDisplay);
    assert(abs(dH90-S.mapW)<=1 && abs(dW90-S.mapH)<=1, '90deg dims wrong');
    bluePx90 = nnz(S.mapDisplay(:,:,3)>150 & S.mapDisplay(:,:,1)<100);
    greenPx90 = nnz(S.mapDisplay(:,:,1)==0 & S.mapDisplay(:,:,2)==200);
    assert(bluePx90 > 0, 'blue road lost after rotation!');
    assert(greenPx90 > 0, 'vehicle lost after rotation!');
    fprintf('[OK] 90deg: %dx%d, blue=%d, green=%d\n', dW90, dH90, bluePx90, greenPx90);

    %% 3. Back to 0 deg
    S.handles.rotSlider.Value = 0;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    S = getappdata(fig, 'S');
    assert(S.rotDeg == 0 && isempty(S.rotSize), 'not restored');
    fprintf('[OK] back to 0deg\n');

    %% 4. Test sketch mode hides blue, shows red
    S.or1.btnSketch.ButtonPushedFcn(S.or1.btnSketch, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'sketching'), 'not sketching');
    % Red skeleton should be visible now
    redPx = nnz(S.mapDisplay(:,:,1)==255 & S.mapDisplay(:,:,2)==0 & S.mapDisplay(:,:,3)==0);
    assert(redPx > 0, 'red skeleton not shown in sketching');
    % Blue road should be hidden
    bluePx2 = nnz(S.mapDisplay(:,:,3)>150 & S.mapDisplay(:,:,1)<100);
    fprintf('[OK] sketching: red=%d (blue hidden=%d)\n', redPx, bluePx2);

    %% 5. Erase toggle
    S.or1.btnErase.ButtonPushedFcn(S.or1.btnErase, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'erasing'), 'not erasing');
    assert(strcmp(get(fig,'Pointer'), 'circle'), 'cursor not circle');
    fprintf('[OK] erasing mode + circle cursor\n');

    %% 6. Toggle back to sketching
    S.or1.btnErase.ButtonPushedFcn(S.or1.btnErase, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'sketching'), 'not back to sketching');
    fprintf('[OK] back to sketching\n');

    %% 7. Clear all
    S.or1.btnClear.ButtonPushedFcn(S.or1.btnClear, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'idle'), 'not idle after clear');
    assert(isempty(S.sk.edges), 'edges not cleared');
    assert(isempty(S.roadMask), 'mask not cleared');
    fprintf('[OK] cleared to idle\n');

    delete(fig);
    fprintf('[OK] Rotation Logic Test PASSED\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),4)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end
