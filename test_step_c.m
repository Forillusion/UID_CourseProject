%TEST_STEP_C  Step C test: road mask generation + visualization
fprintf('========== Step C Test ==========\n');

%% 1. Test genRoadMask with a simple skeleton
% One horizontal edge from (100,100) to (300,100), halfWidth=3
nodes = [100 100; 300 100];
edges = [1 2];
mapW = 500; mapH = 200;
halfW = 3;
mask = genRoadMask(nodes, edges, halfW, mapW, mapH);
assert(size(mask,1)==mapH && size(mask,2)==mapW, 'mask size wrong');
% Center of the edge should be road
assert(mask(100,200)==1, 'center pixel not road');
% Above/below the road should NOT be road (beyond halfWidth)
assert(mask(100+halfW+2,200)==0, 'pixel beyond halfWidth should not be road');
assert(mask(100-halfW-2,200)==0, 'pixel beyond halfWidth should not be road');
% Pixels within halfWidth should be road
assert(all(mask(100-2:100+2,200)), 'pixels within halfWidth should be road');
fprintf('[OK] genRoadMask horizontal edge: %d road pixels\n', sum(mask(:)));

%% 2. Test with vertical edge
nodes2 = [200 50; 200 150];
edges2 = [1 2];
mask2 = genRoadMask(nodes2, edges2, 2, mapW, mapH);
assert(mask2(100,200)==1, 'vertical center not road');
assert(mask2(100,200+4)==0, 'beyond width not road');
fprintf('[OK] genRoadMask vertical edge: %d road pixels\n', sum(mask2(:)));

%% 3. Test with diagonal edge
nodes3 = [100 50; 400 180];
edges3 = [1 2];
mask3 = genRoadMask(nodes3, edges3, 3, mapW, mapH);
% midpoint should be road
mid = [250 115];
assert(mask3(mid(2),mid(1))==1, 'diagonal midpoint not road');
fprintf('[OK] genRoadMask diagonal edge: %d road pixels\n', sum(mask3(:)));

%% 4. Test empty edges
mask4 = genRoadMask(zeros(0,2), zeros(0,2,'int32'), 3, mapW, mapH);
assert(sum(mask4(:))==0, 'empty edges should give empty mask');
fprintf('[OK] genRoadMask empty: 0 pixels\n');

%% 5. Test bounding box optimization
% Edge in corner, mask should only affect nearby region
nodes5 = [10 10; 20 20];
edges5 = [1 2];
mask5 = genRoadMask(nodes5, edges5, 2, mapW, mapH);
affectedCols = find(any(mask5,1));
assert(max(affectedCols) < 30, 'bounding box leak - far cols affected');
fprintf('[OK] genRoadMask bounding box contained\n');

%% 6. Test halfWidth scaling
maskNarrow = genRoadMask(nodes, edges, 1, mapW, mapH);
maskWide = genRoadMask(nodes, edges, 8, mapW, mapH);
assert(sum(maskWide(:)) > sum(maskNarrow(:)), 'wider should have more pixels');
fprintf('[OK] halfWidth scaling: narrow=%d, wide=%d\n', sum(maskNarrow(:)), sum(maskWide(:)));

fprintf('\n========== Step C Test PASSED ==========\n');


%% ===== Local functions =====
function mask = genRoadMask(nodes, edges, halfWidth, mapW, mapH)
    mask = false(mapH, mapW);
    tol = halfWidth + 1;
    for i = 1:size(edges, 1)
        ni = edges(i,1); nj = edges(i,2);
        A = nodes(ni,:); B = nodes(nj,:);
        cMin = max(1, floor(min(A(1),B(1)) - tol));
        cMax = min(mapW, ceil(max(A(1),B(1)) + tol));
        rMin = max(1, floor(min(A(2),B(2)) - tol));
        rMax = min(mapH, ceil(max(A(2),B(2)) + tol));
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
