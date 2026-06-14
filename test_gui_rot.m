%TEST_GUI_ROT  Rotation logic test (ASCII comments only)
fprintf('========== Rotation Logic Test ==========\n');
try
    fig = main();
    S = getappdata(fig, 'S');

    % Setup skeleton + vehicle
    S.sk.nodes = [100 100; 400 100; 400 500];
    S.sk.edges = [1 2; 2 3];
    S.vehicles(1).id = 1; S.vehicles(1).cx = 200; S.vehicles(1).cy = 100;
    S.vehicles(1).angle = 0; S.vehicles(1).dispScale = 3;
    S.nextIVid = 2;
    setappdata(fig, 'S', S);

    %% 1. 0 deg: display size == original
    S.handles.rotSlider.Value = 0;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    S = getappdata(fig, 'S');
    [dH0,dW0,~] = size(S.mapDisplay);
    assert(isempty(S.rotSize), 'rotSize should be empty at 0deg');
    assert(dH0==S.mapH && dW0==S.mapW, sprintf('0deg size: %dx%d vs %dx%d', dW0,dH0,S.mapW,S.mapH));
    fprintf('[OK] 0deg: %dx%d (matches original)\n', dW0, dH0);

    %% 2. Rotate 90 deg
    S.handles.rotSlider.Value = 90;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    S = getappdata(fig, 'S');
    assert(S.rotDeg == 90, 'rotDeg not 90');
    [dH90,dW90,~] = size(S.mapDisplay);
    assert(abs(dH90 - S.mapW)<=1 && abs(dW90 - S.mapH)<=1, ...
        sprintf('90deg dims wrong: %dx%d expect ~%dx%d', dW90,dH90,S.mapH,S.mapW));
    fprintf('[OK] 90deg: %dx%d (swapped)\n', dW90, dH90);

    %% 3. Skeleton + vehicle preserved after rotation
    redPx = nnz(S.mapDisplay(:,:,1)==255 & S.mapDisplay(:,:,2)==0 & S.mapDisplay(:,:,3)==0);
    greenPx = nnz(S.mapDisplay(:,:,1)==0 & S.mapDisplay(:,:,2)==200 & S.mapDisplay(:,:,3)==0);
    assert(redPx > 0, 'skeleton lost after rotation!');
    assert(greenPx > 0, 'vehicle lost after rotation!');
    fprintf('[OK] after rotation: red=%d, green=%d preserved\n', redPx, greenPx);

    %% 4. Inverse-rotation coordinate mapping (pure math test)
    %   Simulate: display center should map back to original center
    S = getappdata(fig, 'S');
    newH = S.rotSize(1); newW = S.rotSize(2);
    % display center click
    colD = newW/2; rowD = newH/2;
    [colO, rowO] = invRot(colD, rowD, S.rotDeg, newW, newH, S.mapW, S.mapH);
    dist = norm([colO,rowO] - [S.mapW/2, S.mapH/2]);
    assert(dist < 3, sprintf('center inverse-rot off: (%.1f,%.1f) dist=%.1f', colO,rowO,dist));
    fprintf('[OK] center inverse-rotation: (%.1f,%.1f) dist=%.2f\n', colO, rowO, dist);

    % A point in the rotated black margin should map outside original.
    % For 90deg the bbox is tight, so test at 45deg where margins exist.
    S.handles.rotSlider.Value = 45;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    S = getappdata(fig, 'S');
    newH2 = S.rotSize(1); newW2 = S.rotSize(2);
    % corner of 45deg display is in the black triangular margin
    [colO2, rowO2] = invRot(1, 1, 45, newW2, newH2, S.mapW, S.mapH);
    outside = (colO2<1)||(colO2>S.mapW)||(rowO2<1)||(rowO2>S.mapH);
    assert(outside, sprintf('45deg corner should be outside: (%.1f,%.1f)', colO2, rowO2));
    fprintf('[OK] 45deg corner (1,1) maps outside original -> invalid\n');

    %% 6. Back to 0 deg
    S.handles.rotSlider.Value = 0;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    S = getappdata(fig, 'S');
    assert(S.rotDeg == 0 && isempty(S.rotSize), 'not restored to 0deg');
    [dH1,dW1,~] = size(S.mapDisplay);
    assert(dH1==S.mapH && dW1==S.mapW, '0deg restore size wrong');
    fprintf('[OK] back to 0deg: %dx%d\n', dW1, dH1);

    delete(fig);
    fprintf('[OK] Rotation Logic Test PASSED\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),4)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end


%% Local function: inverse-rotation (copy of getPointerOnAxes math)
function [col, row] = invRot(colD, rowD, deg, newW, newH, mapW, mapH)
    th = deg2rad(deg);
    c = cos(th); s = sin(th);
    x = colD - newW/2;
    y = rowD - newH/2;
    col =  x*c + y*s + mapW/2;
    row = -x*s + y*c + mapH/2;
end
