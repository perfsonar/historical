
function drawFilledPolygon(ctx,shape,color) {
    if (color != null) {
        ctx.strokeStyle = color;
        ctx.fillStyle = color;
    }

    ctx.beginPath();

    ctx.moveTo(shape[0][0],shape[0][1]);

    for(p in shape)
        if (p > 0) ctx.lineTo(shape[p][0],shape[p][1]);

    ctx.lineTo(shape[0][0],shape[0][1]);
    ctx.fill();
};

function translateShape(shape,x,y) {
    var rv = [];
    for(p in shape)
        rv.push([ shape[p][0] + x, shape[p][1] + y ]);
    return rv;
};

function rotateShape(shape,ang) {
    var rv = [];
    for(p in shape)
        rv.push(rotatePoint(ang,shape[p][0],shape[p][1]));
    return rv;
};

function rotatePoint(ang,x,y) {
    return [ (x * Math.cos(ang)) - (y * Math.sin(ang)), (x * Math.sin(ang)) + (y * Math.cos(ang)) ];
};

function drawArrow(ctx,x1,y1,x2,y2,color,scale) {
    var ang = Math.atan2(y2-y1,x2-x1);

    // default size for the arrow
    var arrow_head_height = 6;
    var arrow_height_width  = 4;
    var line_width   = 2;

    arrow_head_height *= scale;
    arrow_height_width  *= scale;
    line_width   *= scale;

    var arrow = [
        [ 0, 0 ],
        [ -arrow_head_height, -arrow_height_width ],
        [ -arrow_head_height, arrow_height_width]
            ];

    var line_x2 = x2-Math.cos(ang)*arrow_head_height;
    var line_y2 = y2-Math.sin(ang)*arrow_head_height;

    var prevStrokeStyle = ctx.strokeStyle;
    var prevLineWidth   = ctx.lineWidth;
    var prevFillStyle   = ctx.fillStyle;

    ctx.beginPath();
    if (color != null) {
        ctx.strokeStyle = color;
    }
    if (scale != null) {
        ctx.lineWidth = line_width;
    }
    ctx.moveTo(x1,y1);
    ctx.lineTo(line_x2,line_y2);
    ctx.stroke();

    drawFilledPolygon(ctx,translateShape(rotateShape(arrow,ang),x2,y2),color);

    ctx.fillStyle   = prevFillStyle;
    ctx.strokeStyle = prevStrokeStyle;
    ctx.lineWidth   = prevLineWidth;
};
