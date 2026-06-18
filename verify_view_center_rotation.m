fig = main();
S = getappdata(fig, 'S');

target = [1000.5, 600.5];
S.viewZoom = 2;
S.viewCenter = target;
setappdata(fig, 'S', S);
set(S.ax, ...
    'XLim', [target(1) - S.dispW / 4, target(1) + S.dispW / 4], ...
    'YLim', [target(2) - S.dispH / 4, target(2) + S.dispH / 4]);

cb = S.handles.rotSlider.ValueChangedFcn;
S.handles.rotSlider.Value = 45;
cb(S.handles.rotSlider, []);

S = getappdata(fig, 'S');
th = S.rotDeg * pi / 180;
c = cos(th);
s = sin(th);
corners = [0.5 0.5; S.mapW + 0.5 0.5; S.mapW + 0.5 S.mapH + 0.5; 0.5 S.mapH + 0.5];
centered = corners - [S.rotCX S.rotCY];
rotCorners = [ ...
    centered(:,1) * c - centered(:,2) * s + S.rotCX, ...
    centered(:,1) * s + centered(:,2) * c + S.rotCY];
shiftCol = min(rotCorners(:,1));
shiftRow = min(rotCorners(:,2));
expected = [S.rotCX - shiftCol + 1, S.rotCY - shiftRow + 1];

fprintf('rotCenter=[%.1f %.1f]\n', S.rotCX, S.rotCY);
fprintf('viewCenter=[%.1f %.1f]\n', S.viewCenter);
fprintf('expected=[%.1f %.1f]\n', expected);

assert(norm([S.rotCX S.rotCY] - target) < 1.5, ...
    'rotation anchor did not track current view center');
assert(norm(S.viewCenter - expected) < 1.5, ...
    'view center did not stay on rotated anchor');

close(fig);
