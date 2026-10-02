import gpu.BufferUsage;
import gpu.ColorWrite;
import gpu.GpuBufferDescriptor;
import gpu.GpuInstance;
import gpu.GpuRequestAdapterOptions;
import gpu.GpuSurfaceConfiguration;
import gpu.Power;
import gpu.PresentMode;
import gpu.TextureUsage;
import gpu.VertexFormat;
import gpu.VertexStepMode;
import window.Window;
import window.WindowAttributes;

/**
	Opens an xwindow window, hands it to xgpu as a surface and draws an orange
	triangle on every redraw, natively or in Ash's page.

	    Triangle [--seconds S] [--poll] [--capture frame.png]

	Prints `presented N frame(s)` and exits 0 when frames were presented, 1
	otherwise. `--capture` screenshots the window's inner area with macOS
	`screencapture` once frames are on screen; in a page the driver takes the
	screenshot instead. scripts/gpu_test.sh checks the picture.
**/
class Triangle {
	static final SHADER = '
		@vertex
		fn vs(@location(0) position: vec2<f32>) -> @builtin(position) vec4<f32> {
			return vec4<f32>(position, 0.0, 1.0);
		}
		@fragment
		fn fs() -> @location(0) vec4<f32> {
			return vec4<f32>(0.95, 0.45, 0.1, 1.0);
		}
	';

	// Corners in clip space; examples/gpu/triangle.mjs expects this shape.
	static final CORNERS = [-0.8, -0.65, 0.8, -0.65, 0.0, 0.8];

	// --poll: poll a future before awaiting it. Natively Ash's await can miss
	// its wake while a window is open (ash git-bug 4855ac51952dc499ed6427710546ad9860e5ee3dc6030569b698a2b968aba821);
	// a page completes a future only while await has suspended the program,
	// so polling there never ends.
	static var poll = false;

	static function settled<T>(future:ash.Future<T>):T {
		if (poll)
			while (!future.isReady())
				Sys.sleep(0.01);
		return future.await();
	}

	static function check(ok:Bool, message:String) {
		if (!ok)
			throw message;
	}

	static function main() {
		var seconds = 4.0;
		var capture:String = null;
		var args = Sys.args();
		var i = 0;
		while (i < args.length) {
			switch (args[i]) {
				case "--seconds":
					seconds = Std.parseFloat(args[++i]);
				case "--capture":
					capture = args[++i];
				case "--poll":
					poll = true;
				default:
			}
			i++;
		}
		try {
			var frames = run(seconds, capture);
			Sys.println('presented $frames frame(s)');
			if (frames == 0) {
				Sys.println("FAIL: no frame was presented");
				Sys.exit(1);
			}
		} catch (e:Dynamic) {
			Sys.println('FAIL: $e');
			Sys.exit(1);
		}
	}

	static function run(seconds:Float, capture:String):Int {
		var attributes = new WindowAttributes();
		attributes.title("xwindow + xgpu");
		attributes.width(480);
		attributes.height(300);
		var window = Window.open(attributes);
		check(window.valid() && window.width() > 0, "window creation failed");

		var instance = new GpuInstance();
		var surface = instance.surface(window.platform(), window.raw(0), window.raw(1), window.raw(2), window.raw(3));
		check(surface.valid(), 'platform ${window.platform()} gave no GPU surface');
		var options = new GpuRequestAdapterOptions();
		options.powerPreference(HighPerformance);
		options.compatibleSurface(surface);
		var adapter = settled(instance.requestAdapterWith(options));
		check(adapter.valid(), "no GPU adapter is available");
		var device = settled(adapter.requestDevice());
		check(device.valid(), "GPU device creation failed");
		var queue = device.queue();
		var format = surface.preferredFormat(adapter);
		var capabilities = surface.capabilities(adapter);
		check((capabilities.usages() & TextureUsage.RENDER_ATTACHMENT) != 0, "the surface cannot be rendered to");
		var alpha = capabilities.alphaMode(0);

		// The surface follows the window's physical size.
		function configure() {
			if (window.width() <= 0 || window.height() <= 0)
				return;
			var configuration = new GpuSurfaceConfiguration(format, window.width(), window.height());
			configuration.presentMode(Fifo);
			configuration.alphaMode(alpha);
			device.configureSurfaceWith(surface, configuration);
		}
		configure();

		var vertexData = haxe.io.Bytes.alloc(CORNERS.length * 4);
		for (i in 0...CORNERS.length)
			vertexData.setFloat(i * 4, CORNERS[i]);
		var vertices = device.createBuffer(new GpuBufferDescriptor(vertexData.length, BufferUsage.VERTEX | BufferUsage.COPY_DST));
		queue.writeBuffer(vertices, 0, vertexData, vertexData.length);
		var shader = device.createShader(SHADER);
		var builder = device.pipeline();
		builder.shader(shader, "vs", "fs");
		builder.vertexBuffer(8, VertexStepMode.Vertex);
		builder.attribute(VertexFormat.Float32x2, 0, 0);
		builder.target(format, ColorWrite.ALL);
		var pipeline = builder.build();
		check(pipeline.valid(), "render pipeline creation failed");
		Sys.println('GPU: ${adapter.name()}; window ${window.width()}x${window.height()} at scale ${window.scaleFactor()}, platform ${window.platform()}');

		var frames = 0;
		function render() {
			var view = surface.acquire();
			if (!view.valid()) {
				configure();
				return;
			}
			var encoder = device.encoder();
			encoder.passColour(view, 0.06, 0.07, 0.09, 1.0);
			encoder.passBegin();
			encoder.renderSetPipeline(pipeline);
			encoder.renderSetVertexBuffer(0, vertices);
			encoder.renderDraw(3, 1);
			encoder.renderEnd();
			encoder.submit(queue);
			queue.presentSurface(surface);
			frames++;
		}

		var started = Sys.time();
		var closed = false;
		window.requestRedraw();
		while (!closed && Sys.time() - started < seconds) {
			switch (window.wait(0.05)) {
				case Closed | Destroyed:
					closed = true;
				case Resized(_, _):
					configure();
				case RedrawRequested:
					render();
					window.requestRedraw();
				default:
			}
			if (capture != null && frames > 0 && Sys.time() - started > seconds / 2) {
				screenshot(window, capture);
				capture = null;
			}
		}

		pipeline.destroy();
		shader.destroy();
		vertices.destroy();
		surface.destroy();
		device.destroy();
		adapter.destroy();
		instance.destroy();
		window.close();
		return frames;
	}

	/**
		The window's inner area, in screen points. The inner area sits at the
		bottom of the outer frame, centred across it, below the title bar.
	**/
	static function screenshot(window:Window, path:String) {
		var scale = window.scaleFactor();
		var left = window.x() + (window.outerWidth() - window.width()) / 2;
		var top = window.y() + window.outerHeight() - window.height();
		var region = [left, top, window.width(), window.height()].map(v -> Std.string(Math.round(v / scale))).join(",");
		var status = Sys.command("screencapture", ["-x", "-R", region, path]);
		Sys.println('captured $region to $path (status $status)');
	}
}
