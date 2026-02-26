package modchart.backend.graphics.renderers;

import flixel.math.FlxPoint;

using flixel.util.FlxColorTransformUtil;

final matrix:Matrix = new Matrix();
final fMatrix:FlxMatrix = new FlxMatrix();
final rotationVector = new Vector3();
final helperVector = new Vector3();

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
final class ArrowRenderer extends BaseRenderer<FlxSprite> {
	inline private function getGraphicVertices(fullWidth:Float, fullHeight:Float, halfWidth:Float, halfHeight:Float, xOff:Float, yOff:Float, flipX:Bool, flipY:Bool) {
	    var hw = flipX ? -halfWidth : halfWidth;
		var hh = flipY ? -halfHeight : halfHeight;

		var fw = flipX ? -fullWidth : fullWidth;
		var fh = flipY ? -fullHeight : fullHeight;

		return [
			// top left
			xOff - hw,
			yOff - hh,
			// top right
			fw + xOff - hw,
			yOff - hh,
			// bottom left
			xOff - hw,
			fh + yOff - hh,
			// bottom right
			fw + xOff - hw,
			fh + yOff - hh
		];
	}

	var __lastOrient:Float = 0;
	var __lastC2:Float = 0;
	var __lastPlayer:Int = -1;

	override public function prepare(arrow:FlxSprite):Null<DrawCommand> {
		if (arrow.alpha <= 0)
			return null;

		final arrowPosition = helperVector;

		final player = Adapter.instance.getPlayerFromArrow(arrow);

		// setup the position
		var arrowTime = Adapter.instance.getTimeFromArrow(arrow);
		var songPos = Adapter.instance.getSongPosition();
		var arrowDiff = arrowTime - songPos;

		final canUseLast = player == __lastPlayer;

		final centered2 = canUseLast ? __lastC2 : (__lastC2 = parent.getPercent('centered2', player));
		final orient = canUseLast ? __lastOrient : (__lastOrient = parent.getPercent('orient', player));

		// apply centered 2 (aka centered path)
		if (Adapter.instance.isTapNote(arrow)) {
			arrowDiff += FlxG.height * 0.25 * centered2;
		} else {
			arrowTime = songPos + (FlxG.height * 0.25 * centered2);
			arrowDiff = arrowTime - songPos;
		}
		var arrowData:ArrowData = {
			hitTime: arrowTime,
			distance: arrowDiff,
			lane: Adapter.instance.getLaneFromArrow(arrow),
			player: player,
			isTapArrow: Adapter.instance.isTapNote(arrow)
		};

		arrowPosition.setTo(Adapter.instance.getDefaultReceptorX(arrowData.lane, arrowData.player) + Manager.ARROW_SIZEDIV2,
			Adapter.instance.getDefaultReceptorY(arrowData.lane, arrowData.player) + Manager.ARROW_SIZEDIV2, 0);

		final output = parent.modifiers.getPath(arrowPosition, arrowData);
		arrowPosition.copyFrom(output.pos.clone());

		// internal mods
		if (orient != 0) {
			final nextOutput = parent.modifiers.getPath(new Vector3(Adapter.instance.getDefaultReceptorX(arrowData.lane, arrowData.player)
				+ Manager.ARROW_SIZEDIV2,
				Adapter.instance.getDefaultReceptorY(arrowData.lane, arrowData.player)
				+ Manager.ARROW_SIZEDIV2),
				arrowData, 1, false, true);
			final thisPos = output.pos;
			final nextPos = nextOutput.pos;

			output.visuals.angleZ += FlxAngle.wrapAngle((-90 + (Math.atan2(nextPos.y - thisPos.y, nextPos.x - thisPos.x) * FlxAngle.TO_DEG)) * orient);
		}

		__lastPlayer = player;

		// prepare the instruction for drawing
		final projectionDepth = arrowPosition.z;
		final depth = projectionDepth;

		var depthScale = 1 / depth;
		arrow._z = (depth - 1) * 1000;

		var fullWidth = arrow.frame.frame.width * arrow.scale.x;
		var fullHeight = arrow.frame.frame.height * arrow.scale.y;

		var halfWidth = arrow.frameWidth * arrow.scale.x * .5;
		var halfHeight = arrow.frameHeight * arrow.scale.y * .5;

		var animOffset = arrow.animation.curAnim?.offset ?? FlxPoint.weak();
		var xOff = (arrow.frame.offset.x - (arrow.frameOffset.x + animOffset.x)) * arrow.scale.x;
		var yOff = (arrow.frame.offset.y - (arrow.frameOffset.y + animOffset.y)) * arrow.scale.y;
		animOffset.putWeak();

		var planeVertices = getGraphicVertices(fullWidth, fullHeight, halfWidth, halfHeight, xOff, yOff, arrow.flipX, arrow.flipY);
		var projectionZ:haxe.ds.Vector<Float> = new haxe.ds.Vector(Math.ceil(planeVertices.length / 2));

		var vertPointer = 0;
		@:privateAccess do {
			rotationVector.setTo(planeVertices[vertPointer], planeVertices[vertPointer + 1], 0);

			// The result of the vert rotation
			var rotation = ModchartUtil.rotate3DVector(rotationVector, output.visuals.angleX, output.visuals.angleY,
				ModchartUtil.getFrameAngle(arrow) + output.visuals.angleZ + arrow.angle);

			// apply skewness
			if (output.visuals.skewX != 0 || output.visuals.skewY != 0) {
				matrix.identity();

				matrix.b = ModchartUtil.tan(output.visuals.skewY * FlxAngle.TO_RAD);
				matrix.c = ModchartUtil.tan(output.visuals.skewX * FlxAngle.TO_RAD);

				rotation.x = matrix.__transformX(rotation.x, rotation.y);
				rotation.y = matrix.__transformY(rotation.x, rotation.y);
			}
			rotation.x = rotation.x * depthScale * output.visuals.scaleX;
			rotation.y = rotation.y * depthScale * output.visuals.scaleY;

			var view = new Vector3(rotation.x + arrowPosition.x, rotation.y + arrowPosition.y, rotation.z);
			// if (Config.CAMERA3D_ENABLED)
			// 	view = parent.camera3D.applyViewTo(view);
			view.z *= 0.001 * Config.Z_SCALE;

			// The result of the perspective projection of rotation
			final projection = this.view.transformVector(view);

			planeVertices[vertPointer] = projection.x;
			planeVertices[vertPointer + 1] = projection.y;

			// stores depth from this vert to use it for perspective correction on uv's
			projectionZ[Math.floor(vertPointer / 2)] = Math.max(0.0001, projection.z);

			vertPointer = vertPointer + 2;
		} while (vertPointer < planeVertices.length);

		// @formatter:off
		var vertices = new NativeVector<Float>(8);
		// top left
		vertices[0] = planeVertices[0];
		vertices[1] = planeVertices[1];
		// top right
		vertices[2] = planeVertices[2];
		vertices[3] = planeVertices[3];

		// botton left
		vertices[4] = planeVertices[4];
		vertices[5] = planeVertices[5];
		// bottom right
		vertices[6] = planeVertices[6];
		vertices[7] = planeVertices[7];

		final uvRectangle = arrow.frame.uv;
		var uvData = new NativeVector<Float>(12);
		var k = 0;

		#if (flixel == "6.1.0")
		// top left
		uvData[k++] = uvRectangle.left;
		uvData[k++] = uvRectangle.right;
		uvData[k++] = 1 / projectionZ[0];
		// top right
		uvData[k++] = uvRectangle.top;
		uvData[k++] = uvRectangle.right;
		uvData[k++] = 1 / projectionZ[1];
		// bottom left
		uvData[k++] = uvRectangle.top;
		uvData[k++] = uvRectangle.bottom;
		uvData[k++] = 1 / projectionZ[2];
		// bottom right
		uvData[k++] = uvRectangle.left;
		uvData[k++] = uvRectangle.bottom;
		uvData[k++] = 1 / projectionZ[3];
		#elseif (flixel >= "6.1.1")
		// top left
		uvData[k++] = uvRectangle.left;
		uvData[k++] = uvRectangle.top;
		uvData[k++] = 1 / projectionZ[0];
		// top right
		uvData[k++] = uvRectangle.right;
		uvData[k++] = uvRectangle.top;
		uvData[k++] = 1 / projectionZ[1];
		// bottom left
		uvData[k++] = uvRectangle.left;
		uvData[k++] = uvRectangle.bottom;
		uvData[k++] = 1 / projectionZ[2];
		// bottom right
		uvData[k++] = uvRectangle.right;
		uvData[k++] = uvRectangle.bottom;
		uvData[k++] = 1 / projectionZ[3];
		#else
		// top left
		uvData[k++] = uvRectangle.x;
		uvData[k++] = uvRectangle.y;
		uvData[k++] = 1 / projectionZ[0];
		// top right
		uvData[k++] = uvRectangle.width;
		uvData[k++] = uvRectangle.y;
		uvData[k++] = 1 / projectionZ[1];
		// bottom left
		uvData[k++] = uvRectangle.x;
		uvData[k++] = uvRectangle.height;
		uvData[k++] = 1 / projectionZ[2];
		// bottom right
		uvData[k++] = uvRectangle.width;
		uvData[k++] = uvRectangle.height;
		uvData[k++] = 1 / projectionZ[3];
		#end

		var indices = new NativeVector<Int>(6);

		// triangle 1
		indices[0] = 0;
		indices[1] = 1;
		indices[2] = 2;

		// triangle 2
		indices[3] = 1;
		indices[4] = 3;
		indices[5] = 2;

		// @formatter:on
		final absGlow = output.visuals.glow * 255;
		final negGlow = 1 - output.visuals.glow;

		if ((arrow.alpha * output.visuals.alpha) <= 0)
			return null;

		var color = new ColorTransform(negGlow, negGlow, negGlow, arrow.alpha * output.visuals.alpha, Math.round(output.visuals.glowR * absGlow),
			Math.round(output.visuals.glowG * absGlow), Math.round(output.visuals.glowB * absGlow));

		// make the instruction
		var dc:DrawCommand = {
			parent: arrow,
			graphic: arrow.graphic,
			antialiasing: arrow.antialiasing,
			blend: arrow.blend,
			cameras: ModchartUtil.resolveCameras(parent, arrow),
			shader: arrow.shader,

			vertices: vertices,
			uvs: uvData,
			indices: indices,
			color: color,
			isColored: color.hasRGBMultipliers() || color.alphaMultiplier != 1,
			hasColorOffsets: color.hasRGBAOffsets()
		};
		return dc;
	}
}
