// Written in the D programming language.

/**
This module contains drawing buffer implementation.


Synopsis:

----
import dlangui.graphics.drawbuf;

----

Copyright: Vadim Lopatin, 2014
License:   Boost License 1.0
Authors:   Vadim Lopatin, coolreader.org@gmail.com
*/
module dlangui.graphics.drawbuf;

public import dlangui.core.types;
import dlangui.core.logger;
import dlangui.graphics.colors;


/**
 * 9-patch image scaling information (see Android documentation).
 *
 * 
 */
struct NinePatch {
    /// frame (non-scalable) part size for left, top, right, bottom edges.
    Rect frame;
    /// padding (distance to content area) for left, top, right, bottom edges.
    Rect padding;
}

version (USE_OPENGL) {
    /// non thread safe
    private __gshared uint drawBufIdGenerator = 0;
}

/// drawing buffer - image container which allows to perform some drawing operations
class DrawBuf : RefCountedObject {
    protected Rect _clipRect;
    protected NinePatch * _ninePatch;
	protected uint _alpha;

	/// get current alpha setting (to be applied to all drawing operations)
	@property uint alpha() { return _alpha; }
	/// set new alpha setting (to be applied to all drawing operations)
	@property void alpha(uint alpha) {
		_alpha = alpha;
		if (_alpha > 0xFF)
			_alpha = 0xFF;
	}

	/// apply additional transparency to current drawbuf alpha value
	void addAlpha(uint alpha) {
		_alpha = blendAlpha(_alpha, alpha);
	}

	/// applies current drawbuf alpha to argb color value
	uint applyAlpha(uint argb) {
		if (!_alpha)
			return argb; // no drawbuf alpha
		uint a1 = (argb >> 24) & 0xFF;
		if (a1 == 0xFF)
			return argb; // fully transparent
		uint a2 = _alpha & 0xFF;
		uint a = blendAlpha(a1, a2);
		return (argb & 0xFFFFFF) | (a << 24);
	}

    version (USE_OPENGL) {
        protected uint _id;
        /// unique ID of drawbug instance, for using with hardware accelerated rendering for caching
        @property uint id() { return _id; }
    }

    this() {
        version (USE_OPENGL) {
            _id = drawBufIdGenerator++;
        }
		debug _instanceCount++;
    }

	debug private static __gshared int _instanceCount;
	debug @property static int instanceCount() { return _instanceCount; }
	~this() {
		debug _instanceCount--;
		clear();
	}

    protected void function(uint) _onDestroyCallback;
    @property void onDestroyCallback(void function(uint) callback) { _onDestroyCallback = callback; }
    @property void function(uint) onDestroyCallback() { return _onDestroyCallback; }

    // ===================================================
    // 9-patch functions (image scaling using 9-patch markup - unscaled frame and scaled middle parts).
    // See Android documentation for details.

    /// get nine patch information pointer, null if this is not a nine patch image buffer
    @property const (NinePatch) * ninePatch() const { return _ninePatch; }
    /// set nine patch information pointer, null if this is not a nine patch image buffer
    @property void ninePatch(NinePatch * ninePatch) { _ninePatch = ninePatch; }
    /// check whether there is nine-patch information available for drawing buffer
    @property bool hasNinePatch() { return _ninePatch !is null; }
    /// override to detect nine patch using image 1-pixel border; returns true if 9-patch markup is found in image.
    bool detectNinePatch() { return false; }

    /// returns current width
    @property int width() { return 0; }
    /// returns current height
    @property int height() { return 0; }

    // ===================================================
    // clipping rectangle functions

    /// init clip rectangle to full buffer size
    void resetClipping() {
        _clipRect = Rect(0, 0, width, height);
    }
    /// returns clipping rectangle, when clipRect.isEmpty == true -- means no clipping.
    @property ref Rect clipRect() { return _clipRect; }
    /// returns clipping rectangle, or (0,0,dx,dy) when no clipping.
    //@property Rect clipOrFullRect() { return _clipRect.empty ? Rect(0,0,width,height) : _clipRect; }
    /// sets new clipping rectangle, when clipRect.isEmpty == true -- means no clipping.
    @property void clipRect(const ref Rect rect) { 
        _clipRect = rect;
        _clipRect.intersect(Rect(0, 0, width, height));
    }
    /// sets new clipping rectangle, intersect with previous one.
    @property void intersectClipRect(const ref Rect rect) {
		//if (_clipRect.empty)
		//	_clipRect = rect;
		//else
		_clipRect.intersect(rect);
        _clipRect.intersect(Rect(0, 0, width, height));
    }
    /// returns true if rectangle is completely clipped out and cannot be drawn.
    @property bool isClippedOut(const ref Rect rect) {
        //Rect rc = clipOrFullRect();
        return !_clipRect.intersects(rect);
    }
    /// apply clipRect and buffer bounds clipping to rectangle
    bool applyClipping(ref Rect rc) {
        //if (!_clipRect.empty())
        rc.intersect(_clipRect);
        if (rc.left < 0)
            rc.left = 0;
        if (rc.top < 0)
            rc.top = 0;
        if (rc.right > width)
            rc.right = width;
        if (rc.bottom > height)
            rc.bottom = height;
        return !rc.empty();
    }
    /// apply clipRect and buffer bounds clipping to rectangle; if clippinup applied to first rectangle, reduce second rectangle bounds proportionally.
    bool applyClipping(ref Rect rc, ref Rect rc2) {
        if (rc.empty || rc2.empty)
            return false;
        //if (!_clipRect.empty())
        if (!rc.intersects(_clipRect))
            return false;
        if (rc.width == rc2.width && rc.height == rc2.height) {
            // unscaled
            //if (!_clipRect.empty) {
                if (rc.left < _clipRect.left) {
                    rc2.left += _clipRect.left - rc.left;
                    rc.left = _clipRect.left;
                }
                if (rc.top < _clipRect.top) {
                    rc2.top += _clipRect.top - rc.top;
                    rc.top = _clipRect.top;
                }
                if (rc.right > _clipRect.right) {
                    rc2.right -= rc.right - _clipRect.right;
                    rc.right = _clipRect.right;
                }
                if (rc.bottom > _clipRect.bottom) {
                    rc2.bottom -= rc.bottom - _clipRect.bottom;
                    rc.bottom = _clipRect.bottom;
                }
            //}
            if (rc.left < 0) {
                rc2.left += -rc.left;
                rc.left = 0;
            }
            if (rc.top < 0) {
                rc2.top += -rc.top;
                rc.top = 0;
            }
            if (rc.right > width) {
                rc2.right -= rc.right - width;
                rc.right = width;
            }
            if (rc.bottom > height) {
                rc2.bottom -= rc.bottom - height;
                rc.bottom = height;
            }
        } else {
            // scaled
            int dstdx = rc.width;
            int dstdy = rc.height;
            int srcdx = rc2.width;
            int srcdy = rc2.height;
            //if (!_clipRect.empty) {
                if (rc.left < _clipRect.left) {
                    rc2.left += (_clipRect.left - rc.left) * srcdx / dstdx;
                    rc.left = _clipRect.left;
                }
                if (rc.top < _clipRect.top) {
                    rc2.top += (_clipRect.top - rc.top) * srcdy / dstdy;
                    rc.top = _clipRect.top;
                }
                if (rc.right > _clipRect.right) {
                    rc2.right -= (rc.right - _clipRect.right) * srcdx / dstdx;
                    rc.right = _clipRect.right;
                }
                if (rc.bottom > _clipRect.bottom) {
                    rc2.bottom -= (rc.bottom - _clipRect.bottom) * srcdy / dstdy;
                    rc.bottom = _clipRect.bottom;
                }
            //}
            if (rc.left < 0) {
                rc2.left -= (rc.left) * srcdx / dstdx;
                rc.left = 0;
            }
            if (rc.top < 0) {
                rc2.top -= (rc.top) * srcdy / dstdy;
                rc.top = 0;
            }
            if (rc.right > width) {
                rc2.right -= (rc.right - width) * srcdx / dstdx;
                rc.right = width;
            }
            if (rc.bottom > height) {
                rc2.bottom -= (rc.bottom - height) * srcdx / dstdx;
                rc.bottom = height;
            }
        }
        return !rc.empty() && !rc2.empty();
    }
    /// reserved for hardware-accelerated drawing - begins drawing batch
	void beforeDrawing() { _alpha = 0; }
    /// reserved for hardware-accelerated drawing - ends drawing batch
    void afterDrawing() { }
    /// returns buffer bits per pixel
    @property int bpp() { return 0; }
    // returns pointer to ARGB scanline, null if y is out of range or buffer doesn't provide access to its memory
    //uint * scanLine(int y) { return null; }
    /// resize buffer
    abstract void resize(int width, int height);

    //========================================================
    // Drawing methods.

    /// fill the whole buffer with solid color (no clipping applied)
    abstract void fill(uint color);
    /// fill rectangle with solid color (clipping is applied)
    abstract void fillRect(Rect rc, uint color);
    /// draw 8bit alpha image - usually font glyph using specified color (clipping is applied)
	abstract void drawGlyph(int x, int y, Glyph * glyph, uint color);
    /// draw source buffer rectangle contents to destination buffer
    abstract void drawFragment(int x, int y, DrawBuf src, Rect srcrect);
    /// draw source buffer rectangle contents to destination buffer rectangle applying rescaling
    abstract void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect);
    /// draw unscaled image at specified coordinates
    void drawImage(int x, int y, DrawBuf src) {
        drawFragment(x, y, src, Rect(0, 0, src.width, src.height));
    }
    /// draws rectangle frame of specified color and widths (per side), and optinally fills inner area
    void drawFrame(Rect rc, uint frameColor, Rect frameSideWidths, uint innerAreaColor = 0xFFFFFFFF) {
        // draw frame
        if (!isFullyTransparentColor(frameColor)) {
            Rect r;
            // left side
            r = rc;
            r.right = r.left + frameSideWidths.left;
            if (!r.empty)
                fillRect(r, frameColor);
            // right side
            r = rc;
            r.left = r.right - frameSideWidths.right;
            if (!r.empty)
                fillRect(r, frameColor);
            // top side
            r = rc;
            r.left += frameSideWidths.left;
            r.right -= frameSideWidths.right;
            Rect rc2 = r;
            rc2.bottom = r.top + frameSideWidths.top;
            if (!rc2.empty)
                fillRect(rc2, frameColor);
            // bottom side
            rc2 = r;
            rc2.top = r.bottom - frameSideWidths.bottom;
            if (!rc2.empty)
                fillRect(rc2, frameColor);
        }
        // draw internal area
        if (!isFullyTransparentColor(innerAreaColor)) {
            rc.left += frameSideWidths.left;
            rc.top += frameSideWidths.top;
            rc.right -= frameSideWidths.right;
            rc.bottom -= frameSideWidths.bottom;
            if (!rc.empty)
                fillRect(rc, innerAreaColor);
        }
    }

    /// draw focus rectangle; vertical gradient supported - colors[0] is top color, colors[1] is bottom color
    void drawFocusRect(Rect rc, const uint[] colors) {
        // override for faster performance when using OpenGL
        if (colors.length < 1)
            return;
        uint color1 = colors[0];
        uint color2 = colors.length > 1 ? colors[1] : color1;
        if (isFullyTransparentColor(color1) && isFullyTransparentColor(color2))
            return;
        // draw horizontal lines
        for (int x = rc.left; x < rc.right; x++) {
            if ((x ^ rc.top) & 1)
                fillRect(Rect(x, rc.top, x + 1, rc.top + 1), color1);
            if ((x ^ (rc.bottom - 1)) & 1)
                fillRect(Rect(x, rc.bottom - 1, x + 1, rc.bottom), color2);
        }
        // draw vertical lines
        for (int y = rc.top + 1; y < rc.bottom - 1; y++) {
            uint color = color1 == color2 ? color1 : blendARGB(color2, color1, 255 / (rc.bottom - rc.top));
            if ((y ^ rc.left) & 1)
                fillRect(Rect(rc.left, y, rc.left + 1, y + 1), color);
            if ((y ^ (rc.right - 1)) & 1)
                fillRect(Rect(rc.right - 1, y, rc.right, y + 1), color);
        }
    }

    /// create drawbuf with copy of current buffer with changed colors (returns this if not supported)
    DrawBuf transformColors(ref ColorTransform transform) {
        return this;
    }

    void clear() {
		resetClipping();
    }
}

alias DrawBufRef = Ref!DrawBuf;

/// RAII setting/restoring of clip rectangle
struct ClipRectSaver {
    private DrawBuf _buf;
    private Rect _oldClipRect;
	private uint _oldAlpha;
    /// apply (intersect) new clip rectangle and alpha to draw buf; restore 
    this(DrawBuf buf, ref Rect newClipRect, uint newAlpha = 0) {
        _buf = buf;
        _oldClipRect = buf.clipRect;
		_oldAlpha = buf.alpha;
        buf.intersectClipRect(newClipRect);
		if (newAlpha)
			buf.addAlpha(newAlpha);
    }
    ~this() {
        _buf.clipRect = _oldClipRect;
		_buf.alpha = _oldAlpha;
    }
}

class ColorDrawBufBase : DrawBuf {
    int _dx;
    int _dy;
    /// returns buffer bits per pixel
    override @property int bpp() { return 32; }
    @property override int width() { return _dx; }
    @property override int height() { return _dy; }

    /// returns pointer to ARGB scanline, null if y is out of range or buffer doesn't provide access to its memory
    uint * scanLine(int y) { return null; }

    /// draw source buffer rectangle contents to destination buffer
    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect) {
        Rect dstrect = Rect(x, y, x + srcrect.width, y + srcrect.height);
        if (applyClipping(dstrect, srcrect)) {
            if (src.applyClipping(srcrect, dstrect)) {
                int dx = srcrect.width;
                int dy = srcrect.height;
                ColorDrawBufBase colorDrawBuf = cast(ColorDrawBufBase) src;
                if (colorDrawBuf !is null) {
                    for (int yy = 0; yy < dy; yy++) {
                        uint * srcrow = colorDrawBuf.scanLine(srcrect.top + yy) + srcrect.left;
                        uint * dstrow = scanLine(dstrect.top + yy) + dstrect.left;
                        if (!_alpha) {
                            // simplified version - no alpha blending
                            for (int i = 0; i < dx; i++) {
                                uint pixel = srcrow[i];
                                uint alpha = pixel >> 24;
                                if (!alpha)
                                    dstrow[i] = pixel;
                                else if (alpha < 254) {
                                    // apply blending
                                    dstrow[i] = blendARGB(dstrow[i], pixel, alpha);
                                }
                            }
                        } else {
                            // combine two alphas
                            for (int i = 0; i < dx; i++) {
                                uint pixel = srcrow[i];
                                uint alpha = blendAlpha(_alpha, pixel >> 24);
                                if (!alpha)
                                    dstrow[i] = pixel;
                                else if (alpha < 254) {
                                    // apply blending
                                    dstrow[i] = blendARGB(dstrow[i], pixel, alpha);
                                }
                            }
                        }

                    }
                }
            }
        }
    }

    /// Create mapping of source coordinates to destination coordinates, for resize.
    private int[] createMap(int dst0, int dst1, int src0, int src1) {
        int dd = dst1 - dst0;
        int sd = src1 - src0;
        int[] res = new int[dd];
        for (int i = 0; i < dd; i++)
            res[i] = src0 + i * sd / dd;
        return res;
    }

    /// draw source buffer rectangle contents to destination buffer rectangle applying rescaling
    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect) {
        //Log.d("drawRescaled ", dstrect, " <- ", srcrect);
        if (_alpha >= 254)
            return; // fully transparent - don't draw
        if (applyClipping(dstrect, srcrect)) {
            int[] xmapArray = createMap(dstrect.left, dstrect.right, srcrect.left, srcrect.right);
            int[] ymapArray = createMap(dstrect.top, dstrect.bottom, srcrect.top, srcrect.bottom);
            int * xmap = xmapArray.ptr;
            int * ymap = ymapArray.ptr;
            int dx = dstrect.width;
            int dy = dstrect.height;
            ColorDrawBufBase colorDrawBuf = cast(ColorDrawBufBase) src;
            if (colorDrawBuf !is null) {
                for (int y = 0; y < dy; y++) {
                    uint * srcrow = colorDrawBuf.scanLine(ymap[y]);
                    uint * dstrow = scanLine(dstrect.top + y) + dstrect.left;
                    if (!_alpha) {
                        // simplified alpha calculation
                        for (int x = 0; x < dx; x++) {
                            uint srcpixel = srcrow[xmap[x]];
                            uint dstpixel = dstrow[x];
                            uint alpha = srcpixel >> 24;
                            if (!alpha)
                                dstrow[x] = srcpixel;
                            else if (alpha < 255) {
                                // apply blending
                                dstrow[x] = blendARGB(dstpixel, srcpixel, alpha);
                            }
                        }
                    } else {
                        // blending two alphas
                        for (int x = 0; x < dx; x++) {
                            uint srcpixel = srcrow[xmap[x]];
                            uint dstpixel = dstrow[x];
                            uint srca = srcpixel >> 24;
                            uint alpha = !srca ? _alpha : blendAlpha(_alpha, srca);
                            if (!alpha)
                                dstrow[x] = srcpixel;
                            else if (alpha < 255) {
                                // apply blending
                                dstrow[x] = blendARGB(dstpixel, srcpixel, alpha);
                            }
                        }
                    }
                }
            }
        }
    }

    /// detect position of black pixels in row for 9-patch markup
    private bool detectHLine(int y, ref int x0, ref int x1) {
        uint * line = scanLine(y);
    	bool foundUsed = false;
        x0 = 0;
        x1 = 0;
    	for (int x = 1; x < _dx - 1; x++) {
    		if (isBlackPixel(line[x])) { // opaque black pixel
    			if (!foundUsed) {
    				x0 = x;
        			foundUsed = true;
    			}
    			x1 = x + 1;
    		}
    	}
        return x1 > x0;
    }

	static bool isBlackPixel(uint c) {
		if (((c >> 24) & 255) > 10)
			return false;
		if (((c >> 16) & 255) > 10)
			return false;
		if (((c >> 8) & 255) > 10)
			return false;
		if (((c >> 0) & 255) > 10)
			return false;
		return true;
	}
	
    /// detect position of black pixels in column for 9-patch markup
    private bool detectVLine(int x, ref int y0, ref int y1) {
    	bool foundUsed = false;
        y0 = 0;
        y1 = 0;
    	for (int y = 1; y < _dy - 1; y++) {
            uint * line = scanLine(y);
    		if (isBlackPixel(line[x])) { // opaque black pixel
    			if (!foundUsed) {
    				y0 = y;
        			foundUsed = true;
    			}
    			y1 = y + 1;
    		}
    	}
        return y1 > y0;
    }
    /// detect nine patch using image 1-pixel border (see Android documentation)
    override bool detectNinePatch() {
        if (_dx < 3 || _dy < 3)
            return false; // image is too small
        int x00, x01, x10, x11, y00, y01, y10, y11;
        bool found = true;
        found = found && detectHLine(0, x00, x01);
        found = found && detectHLine(_dy - 1, x10, x11);
        found = found && detectVLine(0, y00, y01);
        found = found && detectVLine(_dx - 1, y10, y11);
        if (!found)
            return false; // no black pixels on 1-pixel frame
        NinePatch * p = new NinePatch();
        p.frame.left = x00 - 1;
        p.frame.right = _dx - x01 - 1;
        p.frame.top = y00 - 1;
        p.frame.bottom = _dy - y01 - 1;
        p.padding.left = x10 - 1;
        p.padding.right = _dx - x11 - 1;
        p.padding.top = y10 - 1;
        p.padding.bottom = _dy - y11 - 1;
        _ninePatch = p;
		//Log.d("NinePatch detected: frame=", p.frame, " padding=", p.padding, " left+right=", p.frame.left + p.frame.right, " dx=", _dx);
        return true;
    }

	override void drawGlyph(int x, int y, Glyph * glyph, uint color) {
        ubyte[] src = glyph.glyph;
        int srcdx = glyph.blackBoxX;
        int srcdy = glyph.blackBoxY;
		bool clipping = true; //!_clipRect.empty();
		color = applyAlpha(color);
        bool subpixel = glyph.subpixelMode != SubpixelRenderingMode.None;
		for (int yy = 0; yy < srcdy; yy++) {
			int liney = y + yy;
			if (clipping && (liney < _clipRect.top || liney >= _clipRect.bottom))
				continue;
			if (liney < 0 || liney >= _dy)
				continue;
			uint * row = scanLine(liney);
			ubyte * srcrow = src.ptr + yy * srcdx;
			for (int xx = 0; xx < srcdx; xx++) {
				int colx = x + (subpixel ? xx / 3 : xx);
				if (clipping && (colx < _clipRect.left || colx >= _clipRect.right))
					continue;
				if (colx < 0 || colx >= _dx)
					continue;
				uint alpha2 = (color >> 24);
                uint alpha1 = srcrow[xx] ^ 255;
                uint alpha = ((((alpha1 ^ 255) * (alpha2 ^ 255)) >> 8) ^ 255) & 255;
                if (subpixel) {
                    int x0 = xx % 3;
                    ubyte * dst = cast(ubyte*)(row + colx);
                    ubyte * pcolor = cast(ubyte*)(&color);
                    blendSubpixel(dst, pcolor, alpha, x0, glyph.subpixelMode);
                } else {
                    uint pixel = row[colx];
                    if (alpha < 255) {
				        if (!alpha)
					        row[colx] = pixel;
				        else {
					        // apply blending
					        row[colx] = blendARGB(pixel, color, alpha);
				        }
                    }
                }
			}
		}
	}

	void drawGlyphToTexture(int x, int y, Glyph * glyph) {
        ubyte[] src = glyph.glyph;
        int srcdx = glyph.blackBoxX;
        int srcdy = glyph.blackBoxY;
        bool subpixel = glyph.subpixelMode != SubpixelRenderingMode.None;
		for (int yy = 0; yy < srcdy; yy++) {
			int liney = y + yy;
			uint * row = scanLine(liney);
			ubyte * srcrow = src.ptr + yy * srcdx;
			int increment = subpixel ? 3 : 1;
			for (int xx = 0; xx <= srcdx - increment; xx += increment) {
				int colx = x + (subpixel ? xx / 3 : xx);
                if (subpixel) {
                    uint t1 = srcrow[xx];
                    uint t2 = srcrow[xx + 1];
                    uint t3 = srcrow[xx + 2];
                    //uint pixel = ((t2 ^ 0x00) << 24) | ((t1  ^ 0xFF)<< 16) | ((t2 ^ 0xFF) << 8) | (t3 ^ 0xFF);
                    uint pixel = ((t2 ^ 0x00) << 24) | 0xFFFFFF;
					row[colx] = pixel;
                } else {
                    uint alpha1 = srcrow[xx] ^ 0xFF;
                    //uint pixel = (alpha1 << 24) | 0xFFFFFF; //(alpha1 << 16) || (alpha1 << 8) || alpha1;
                    //uint pixel = ((alpha1 ^ 0xFF) << 24) | (alpha1 << 16) | (alpha1 << 8) | alpha1;
                    uint pixel = ((alpha1 ^ 0xFF) << 24) | 0xFFFFFF;
					row[colx] = pixel;
                }
			}
		}
	}

    override void fillRect(Rect rc, uint color) {
        if (applyClipping(rc)) {
            for (int y = rc.top; y < rc.bottom; y++) {
                uint * row = scanLine(y);
                uint alpha = color >> 24;
                if (!alpha) {
                    row[rc.left .. rc.right] = color;
                } else if (alpha < 254) {
                    for (int x = rc.left; x < rc.right; x++) {
                        // apply blending
                        row[x] = blendARGB(row[x], color, alpha);
                    }
                }
            }
        }
    }
}

class GrayDrawBuf : DrawBuf {
    int _dx;
    int _dy;
    /// returns buffer bits per pixel
    override @property int bpp() { return 8; }
    @property override int width() { return _dx; }
    @property override int height() { return _dy; }

    ubyte[] _buf;
    this(int width, int height) {
        resize(width, height);
    }
    ubyte * scanLine(int y) {
        if (y >= 0 && y < _dy)
            return _buf.ptr + _dx * y;
        return null;
    }
    override void resize(int width, int height) {
        if (_dx == width && _dy == height)
            return;
        _dx = width;
        _dy = height;
        _buf.length = _dx * _dy;
        resetClipping();
    }
    override void fill(uint color) {
        int len = _dx * _dy;
        ubyte * p = _buf.ptr;
        ubyte cl = rgbToGray(color);
        for (int i = 0; i < len; i++)
            p[i] = cl;
    }

    /// draw source buffer rectangle contents to destination buffer
    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect) {
        Rect dstrect = Rect(x, y, x + srcrect.width, y + srcrect.height);
        if (applyClipping(dstrect, srcrect)) {
            if (src.applyClipping(srcrect, dstrect)) {
                int dx = srcrect.width;
                int dy = srcrect.height;
                GrayDrawBuf grayDrawBuf = cast (GrayDrawBuf) src;
                if (grayDrawBuf !is null) {
                    for (int yy = 0; yy < dy; yy++) {
                        ubyte * srcrow = grayDrawBuf.scanLine(srcrect.top + yy) + srcrect.left;
                        ubyte * dstrow = scanLine(dstrect.top + yy) + dstrect.left;
                        for (int i = 0; i < dx; i++) {
                            ubyte pixel = srcrow[i];
                            dstrow[i] = pixel;
                        }
                    }
                }
            }
        }
    }

    /// Create mapping of source coordinates to destination coordinates, for resize.
    private int[] createMap(int dst0, int dst1, int src0, int src1) {
        int dd = dst1 - dst0;
        int sd = src1 - src0;
        int[] res = new int[dd];
        for (int i = 0; i < dd; i++)
            res[i] = src0 + i * sd / dd;
        return res;
    }
    /// draw source buffer rectangle contents to destination buffer rectangle applying rescaling
    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect) {
        //Log.d("drawRescaled ", dstrect, " <- ", srcrect);
        if (applyClipping(dstrect, srcrect)) {
            int[] xmap = createMap(dstrect.left, dstrect.right, srcrect.left, srcrect.right);
            int[] ymap = createMap(dstrect.top, dstrect.bottom, srcrect.top, srcrect.bottom);
            int dx = dstrect.width;
            int dy = dstrect.height;
            GrayDrawBuf grayDrawBuf = cast (GrayDrawBuf) src;
            if (grayDrawBuf !is null) {
                for (int y = 0; y < dy; y++) {
                    ubyte * srcrow = grayDrawBuf.scanLine(ymap[y]);
                    ubyte * dstrow = scanLine(dstrect.top + y) + dstrect.left;
                    for (int x = 0; x < dx; x++) {
                        ubyte srcpixel = srcrow[xmap[x]];
                        ubyte dstpixel = dstrow[x];
                        dstrow[x] = srcpixel;
                    }
                }
            }
        }
    }

    /// detect position of black pixels in row for 9-patch markup
    private bool detectHLine(int y, ref int x0, ref int x1) {
        ubyte * line = scanLine(y);
    	bool foundUsed = false;
        x0 = 0;
        x1 = 0;
    	for (int x = 1; x < _dx - 1; x++) {
    		if (line[x] == 0x00000000) { // opaque black pixel
    			if (!foundUsed) {
    				x0 = x;
        			foundUsed = true;
    			}
    			x1 = x + 1;
    		}
    	}
        return x1 > x0;
    }

    /// detect position of black pixels in column for 9-patch markup
    private bool detectVLine(int x, ref int y0, ref int y1) {
    	bool foundUsed = false;
        y0 = 0;
        y1 = 0;
    	for (int y = 1; y < _dy - 1; y++) {
            ubyte * line = scanLine(y);
    		if (line[x] == 0x00000000) { // opaque black pixel
    			if (!foundUsed) {
    				y0 = y;
        			foundUsed = true;
    			}
    			y1 = y + 1;
    		}
    	}
        return y1 > y0;
    }
    /// detect nine patch using image 1-pixel border (see Android documentation)
    override bool detectNinePatch() {
        if (_dx < 3 || _dy < 3)
            return false; // image is too small
        int x00, x01, x10, x11, y00, y01, y10, y11;
        bool found = true;
        found = found && detectHLine(0, x00, x01);
        found = found && detectHLine(_dy - 1, x10, x11);
        found = found && detectVLine(0, y00, y01);
        found = found && detectVLine(_dx - 1, y10, y11);
        if (!found)
            return false; // no black pixels on 1-pixel frame
        NinePatch * p = new NinePatch();
        p.frame.left = x00 - 1;
        p.frame.right = _dy - y01 - 1;
        p.frame.top = y00 - 1;
        p.frame.bottom = _dy - y01 - 1;
        p.padding.left = x10 - 1;
        p.padding.right = _dy - y11 - 1;
        p.padding.top = y10 - 1;
        p.padding.bottom = _dy - y11 - 1;
        _ninePatch = p;
        return true;
    }
	override void drawGlyph(int x, int y, Glyph * glyph, uint color) {
        ubyte[] src = glyph.glyph;
        int srcdx = glyph.blackBoxX;
        int srcdy = glyph.blackBoxY;
		bool clipping = true; //!_clipRect.empty();
        ubyte cl = cast(ubyte)(color & 255);
		for (int yy = 0; yy < srcdy; yy++) {
			int liney = y + yy;
			if (clipping && (liney < _clipRect.top || liney >= _clipRect.bottom))
				continue;
			if (liney < 0 || liney >= _dy)
				continue;
			ubyte * row = scanLine(liney);
			ubyte * srcrow = src.ptr + yy * srcdx;
			for (int xx = 0; xx < srcdx; xx++) {
				int colx = xx + x;
				if (clipping && (colx < _clipRect.left || colx >= _clipRect.right))
					continue;
				if (colx < 0 || colx >= _dx)
					continue;
				uint alpha1 = srcrow[xx] ^ 255;
				uint alpha2 = (color >> 24);
				uint alpha = ((((alpha1 ^ 255) * (alpha2 ^ 255)) >> 8) ^ 255) & 255;
				uint pixel = row[colx];
				if (!alpha)
					row[colx] = cast(ubyte)pixel;
				else if (alpha < 255) {
					// apply blending
					row[colx] = cast(ubyte)blendARGB(pixel, color, alpha);
				}
			}
		}
	}
    override void fillRect(Rect rc, uint color) {
        ubyte cl = rgbToGray(color);
        if (applyClipping(rc)) {
            for (int y = rc.top; y < rc.bottom; y++) {
                ubyte * row = scanLine(y);
                uint alpha = color >> 24;
                for (int x = rc.left; x < rc.right; x++) {
                    if (!alpha)
                        row[x] = cl;
                    else if (alpha < 255) {
                        // apply blending
                        row[x] = blendGray(row[x], cl, alpha);
                    }
                }
            }
        }
    }
}

class ColorDrawBuf : ColorDrawBufBase {
    uint[] _buf;
	/// create ARGB8888 draw buf of specified width and height
    this(int width, int height) {
        resize(width, height);
    }
	/// create copy of ColorDrawBuf
	this(ColorDrawBuf v) {
		this(v.width, v.height);
		//_buf.length = v._buf.length;
		for (int i = 0; i < _buf.length; i++)
			_buf[i] = v._buf[i];
	}
	/// create resized copy of ColorDrawBuf
	this(ColorDrawBuf v, int dx, int dy) {
		this(dx, dy);
        fill(0xFFFFFFFF);
        drawRescaled(Rect(0, 0, dx, dy), v, Rect(0, 0, v.width, v.height));
	}
	void invertAlpha() {
		foreach(pixel; _buf)
			pixel ^= 0xFF000000;
	}
    override uint * scanLine(int y) {
        if (y >= 0 && y < _dy)
            return _buf.ptr + _dx * y;
        return null;
    }
    override void resize(int width, int height) {
        if (_dx == width && _dy == height)
            return;
        _dx = width;
        _dy = height;
        _buf.length = _dx * _dy;
        resetClipping();
    }
    override void fill(uint color) {
        int len = _dx * _dy;
        uint * p = _buf.ptr;
        for (int i = 0; i < len; i++)
            p[i] = color;
    }
    override DrawBuf transformColors(ref ColorTransform transform) {
        if (transform.empty)
            return this;
        bool skipFrame = hasNinePatch;
        ColorDrawBuf res = new ColorDrawBuf(_dx, _dy);
        if (hasNinePatch) {
            NinePatch * p = new NinePatch;
            *p = *_ninePatch;
            res.ninePatch = p;
        }
        for (int y = 0; y < _dy; y++) {
            uint * srcline = scanLine(y);
            uint * dstline = res.scanLine(y);
            bool allowTransformY = !skipFrame || (y !=0 && y != _dy - 1);
            for (int x = 0; x < _dx; x++) {
                bool allowTransformX = !skipFrame || (x !=0 && x != _dx - 1);
                if (!allowTransformX || !allowTransformY)
                    dstline[x] = srcline[x];
                else
                    dstline[x] = transform.transform(srcline[x]);
            }
        }
        return res;
    }
}


