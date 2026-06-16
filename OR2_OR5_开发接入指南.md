# OR2-OR5 后续开发接入指南

项目地址：[https://github.com/Forillusion/UID_CourseProject/tree/master](https://github.com/Forillusion/UID_CourseProject/tree/master)

本文档给后续负责 OR2、OR3、OR4、OR5 的组员使用。现在 OR1 已经做好，并通过 `or1_skeleton.m` 接入 `main.m`。后续功能建议也按同样方式做：每个 OR 单独一个 `.m` 文件，`main.m` 只保留入口按钮和必要的事件分发。

## 1. 当前主程序结构

运行入口：

```matlab
main
```

主要文件：

| 文件 | 作用 |
| --- | --- |
| `main.m` | 主 UI、地图显示、车辆、测距、OR 入口按钮 |
| `or1_skeleton.m` | OR1 道路骨架工具，已完成 |
| `MapForUI.jpg` | 地图图片 |
| `RoadMask.jpg` | Basic 阶段道路 mask，用于不依赖 OR1 时判断道路 |
| `optional_OR1/` | OR1 旧版本、测试和说明备份 |

`main.m` 左侧面板里已有这些入口：

```matlab
h.btnOR1 = addC('button', r, 'Text','OR1 道路骨架', ...
                'ButtonPushedFcn', @(s,e) or1_skeleton('open', fig));
h.btnOR2 = addC('button', r, 'Text','OR2 预留', 'Enable','off');
h.btnOR3 = addC('button', r, 'Text','OR3 预留', 'Enable','off');
h.btnOR4 = addC('button', r, 'Text','OR4 预留', 'Enable','off');
h.btnOR5 = addC('button', r, 'Text','OR5 预留', 'Enable','off');
```

你的任务完成后，只需要把对应按钮从 `Enable','off'` 改成可点击，并接到你的文件。

## 2. 推荐接入方式

每个人新建一个独立文件：

| 任务 | 建议文件名 | 入口函数 |
| --- | --- | --- |
| OR2 | `or2_local_view.m` | `or2_local_view('open', fig)` |
| OR3 | `or3_auto_heading.m` | `or3_auto_heading('open', fig)` |
| OR4 | `or4_street_view.m` | `or4_street_view('open', fig)` |
| OR5 | `or5_path_planning.m` | `or5_path_planning('open', fig)` |

最小模板：

```matlab
function or2_local_view(action, mainFig, varargin)
    switch action
        case 'open'
            do_open(mainFig);
        case 'click'
            do_click(mainFig, varargin{:});
    end
end

function do_open(mainFig)
    S = getappdata(mainFig, 'S');
    S.mode = 'or2';
    setappdata(mainFig, 'S', S);
    S.fn.setStatus(mainFig, 'OR2 已开启。');
end

function do_click(mainFig, col, row, selType)
    %#ok<INUSD>
    S = getappdata(mainFig, 'S');
    % 在这里写点击地图后的逻辑
    setappdata(mainFig, 'S', S);
end
```

接入 `main.m` 按钮示例：

```matlab
h.btnOR2 = addC('button', r, 'Text','OR2 局部地图', ...
                'ButtonPushedFcn', @(s,e) or2_local_view('open', fig));
```

如果你的功能需要点击地图，在 `main.m` 的 `onMouseDown` 里添加一行：

```matlab
case 'or2'
    or2_local_view('click', fig, col, row, selType);
```

只改自己的 case，不要改别人的 mode 名字。

## 3. 全局状态 S 怎么用

主程序所有共享数据都放在 `S` 里：

```matlab
S = getappdata(fig, 'S');
% 修改 S.xxx
setappdata(fig, 'S', S);
```

常用字段：

| 字段 | 说明 |
| --- | --- |
| `S.fig` | 主窗口 |
| `S.ax` | 地图坐标轴 |
| `S.mapOrigin` | 原始地图，只读，不要直接改 |
| `S.mapDisplay` | 当前显示图 |
| `S.mapW`, `S.mapH` | 地图宽高 |
| `S.scale` | 比例尺，`1 像素 = 1.7 米` |
| `S.mode` | 当前鼠标交互模式 |
| `S.sk.nodes` | OR1 骨架节点，格式 `[col, row]` |
| `S.sk.edges` | OR1 骨架边，节点编号从 1 开始 |
| `S.roadMask` | OR1 生成的道路区域，`true` 表示道路 |
| `S.basicRoadMask` | `RoadMask.jpg` 读入的基础道路 mask |
| `S.vehicles` | 车辆列表，每辆车有 `id,cx,cy,angle,dispScale` |
| `S.handles` | 主 UI 控件句柄 |
| `S.fn.refresh` | 刷新地图显示 |
| `S.fn.setStatus` | 改状态栏文字 |
| `S.fn.updateDropdown` | 更新车辆下拉框 |

改完地图或车辆后，通常调用：

```matlab
S.fn.refresh(fig);
```

只改状态提示时：

```matlab
S.fn.setStatus(fig, '你的提示文字');
```

## 4. 坐标约定

地图像素坐标：

```text
col: 从左到右
row: 从上到下
```

世界坐标：

```text
X: 从左到右，单位米
Y: 从下到上，单位米
```

`main.m` 已有转换函数：

```matlab
[wx, wy] = px2world(fig, col, row);
[col, row] = world2px(fig, wx, wy);
```

不要把 `row` 当成世界坐标的 Y。这里最容易错。

## 5. 画图的统一方式

不要直接修改 `S.mapOrigin`。需要叠加自己的效果时，用这个模式：

```matlab
function drawMyResult(mainFig)
    S = getappdata(mainFig, 'S');
    map = buildBaseMap(mainFig);

    % 在 map 上画你的内容，例如：
    % map(row, col, :) = uint8([255 0 0]);

    S.mapDisplay = map;
    S.rotSize = [];
    setappdata(mainFig, 'S', S);
    refreshView(mainFig);
end
```

如果只是改了车辆、道路、骨架等已有数据，优先调用：

```matlab
S.fn.refresh(mainFig);
```

## 6. 各 OR 的数据依赖

### OR2：IV 缩放和局部地图

建议依赖：

| 数据 | 用途 |
| --- | --- |
| `S.vehicles` | 找当前车辆位置 |
| `S.scale` | 米和像素换算 |
| `buildBaseMap(fig)` | 生成基础地图再叠加局部区域 |

建议做法：

1. 新建 `or2_local_view.m`。
2. 弹出一个小窗口，放缩放倍数、局部半径、显示/还原按钮。
3. 缩放只改 `S.vehicles(i).dispScale`。
4. 局部地图用车辆坐标为圆心，半径 `radius_m / S.scale` 转成像素。

### OR3：车辆自动对齐方向

建议依赖：

| 数据 | 用途 |
| --- | --- |
| `S.sk.nodes`, `S.sk.edges` | 找最近道路边，计算道路方向 |
| `S.vehicles` | 修改车辆角度 |
| `ptToSegDist` | 点到道路边距离 |

建议做法：

1. 新建 `or3_auto_heading.m`。
2. 提供“当前车辆自动对齐”按钮。
3. 找离车辆最近的骨架边，用 `atan2d` 算方向。
4. 把结果写进 `S.vehicles(i).angle`，再刷新地图。

注意：如果没有 OR1 骨架，无法可靠判断道路方向，直接提示用户先完成 OR1。

### OR4：虚拟街景

建议依赖：

| 数据 | 用途 |
| --- | --- |
| `S.mapOrigin` | 作为街景采样源 |
| `S.vehicles` 或鼠标点击点 | 相机位置 |
| `S.scale` | 距离换算 |

建议做法：

1. 新建 `or4_street_view.m`。
2. 弹出一个街景窗口，里面放一张 `uiimage` 或 `uiaxes`。
3. 先实现最小版本：用车辆位置和角度生成一张 2D 透视图。
4. 不要改主地图，只在 OR4 窗口显示结果。

### OR5：路径规划

建议依赖：

| 数据 | 用途 |
| --- | --- |
| `S.sk.nodes`, `S.sk.edges` | 路网图 |
| `S.roadMask` | 把用户点击点吸附到道路上 |
| `bresenham` 或 `stampSquare` | 把路径画回地图 |

建议做法：

1. 新建 `or5_path_planning.m`。
2. 设置两个 mode：`or5_start` 和 `or5_end`。
3. 用户点击地图后，找最近骨架节点或最近道路点。
4. 手写 Dijkstra，禁止直接调用图最短路工具。
5. 把路径节点连成绿色线，叠加显示。

## 7. 提交前检查

每个人提交前至少检查：

- [ ] 能从 `main` 启动。
- [ ] 自己的 OR 按钮能打开功能。
- [ ] 不影响 OR1、加载车辆、测距。
- [ ] 没有直接改 `S.mapOrigin`。
- [ ] 修改 `S` 后有 `setappdata(mainFig, 'S', S)`。
- [ ] 需要道路骨架的功能，会在没有 OR1 数据时给出提示。
- [ ] 没有使用课程禁止的高级内置函数。

## 8. 合并顺序建议

1. 每个人只新增自己的 `orX_*.m` 文件。
2. `main.m` 只改两处：按钮入口和 `onMouseDown` 分发。
3. 合并时先合并新增文件，再手动合并 `main.m` 的按钮和 case。
4. 合并后运行 `main`，依次点 OR1 到 OR5 做一次冒烟测试。

这样冲突最少，也方便老师检查每个人负责的部分。
