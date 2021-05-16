const sabaton = @import("root").sabaton;
const platform = @import("main.zig");

pub fn init() void {
  var slice: [35]u32 align(16) = undefined;
  var mbox = @intToPtr([*]volatile u32, @ptrToInt(&slice));
  mbox[0] = 35*4; // size
  mbox[1] = 0; // req

  mbox[2] = 0x48004; // virtual width (ideally for scrolling and double buffering)
  mbox[3] = 8; // buffer size
  mbox[4] = 8; // req/resp code
  mbox[5] = sabaton.fb_width; // base
  mbox[6] = sabaton.fb_height; // size

  mbox[7] = 0x48009; // virtual offset
  mbox[8] = 8; // buffer size
  mbox[9] = 8; // req/resp code
  mbox[10] = 0; // x
  mbox[11] = 0; // y

  mbox[12] = 0x48003; // physical width
  mbox[13] = 8; // buffer size
  mbox[14] = 8; // req/resp code
  mbox[15] = sabaton.fb_width; // base
  mbox[16] = sabaton.fb_height; // size

  mbox[17] = 0x48005; // set bpp
  mbox[18] = 4; // buffer size
  mbox[19] = 4; // req/resp code
  mbox[20] = 32; // the only good bit depth 

  mbox[21] = 0x48006; // pixel format
  mbox[22] = 4; // buffer size
  mbox[23] = 4; // req/resp code
  mbox[24] = 0;

  mbox[25] = 0x40001; // fb addr
  mbox[26] = 8; // buffer size
  mbox[27] = 8; // req/resp code
  mbox[28] = 4096; // req: alignment, resp: addr
  mbox[29] = 0; // size

  mbox[30] = 0x40008; // fb pitch
  mbox[31] = 4; // buffer size
  mbox[32] = 4; // req/resp code
  mbox[33] = 0; // pitch
  
  mbox[34] = 0; // terminator

  platform.mbox_call(8, @ptrToInt(mbox));

  sabaton.fb.pitch = @truncate(u16, mbox[33]);
  sabaton.fb.width = @truncate(u16, mbox[15]);
  sabaton.fb.height = @truncate(u16, mbox[16]);
  sabaton.fb.red_mask_size = 8;
  sabaton.fb.green_mask_size = 8;
  sabaton.fb.blue_mask_size = 8;
  sabaton.fb.bpp = 32;

  sabaton.fb.red_mask_shift = 16; 
  sabaton.fb.green_mask_shift = 8;
  sabaton.fb.blue_mask_shift = 0;
  const bus_addr = mbox[28];
  const arm_addr = bus_addr & 0x3FFFFFFF;

  sabaton.add_framebuffer(arm_addr);  
}
