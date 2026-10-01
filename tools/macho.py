"""Bounded Mach-O/signature inspection. This does not verify cryptographic trust."""
import plistlib
import struct


def region(data, offset, length):
    if offset < 0 or length < 0 or offset + length > len(data):
        raise ValueError('Mach-O range exceeds file')
    return data[offset:offset + length]


def slices(data):
    if data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = data[3] == 0xbf
        count = struct.unpack('>I', region(data, 4, 4))[0]
        if not 1 <= count <= 16:
            raise ValueError('Invalid fat architecture count')
        entry = 32 if wide else 20
        result = []
        bounds = []
        table_end = 8 + count * entry
        region(data, 0, table_end)
        for index in range(count):
            values = struct.unpack('>IIQQII' if wide else '>IIIII', region(data, 8 + index * entry, entry))
            cpu, subtype, offset, size = values[:4]
            if offset < table_end or any(offset < end and start < offset + size for start, end in bounds):
                raise ValueError('Overlapping Mach-O slices/table')
            bounds.append((offset, offset + size))
            item = inspect_slice(region(data, offset, size))
            if item['cpu'] != cpu or item['subtype'] != (subtype & 0xffffff):
                raise ValueError('Fat/slice architecture mismatch')
            result.append(item)
        if len({item['arch'] for item in result}) != count:
            raise ValueError('Duplicate Mach-O architectures')
        return result
    return [inspect_slice(data)]


def signature_entitlements(data):
    magic, size, count = struct.unpack('>III', region(data, 0, 12))
    if magic != 0xfade0cc0 or not 12 <= size <= len(data) or count > 64:
        raise ValueError('Invalid code-signature SuperBlob')
    # LC_CODE_SIGNATURE.datasize can include alignment padding after the SuperBlob.
    data = region(data, 0, size)
    table_end = 12 + count * 8
    region(data, 0, table_end)
    entitlements = None
    code_directory = False
    bounds = []
    slots = set()
    for index in range(count):
        slot, offset = struct.unpack('>II', region(data, 12 + index * 8, 8))
        if offset < table_end:
            raise ValueError('Signature blob overlaps index')
        blob_magic, length = struct.unpack('>II', region(data, offset, 8))
        if length < 8:
            raise ValueError('Invalid signature blob length')
        blob = region(data, offset, length)
        if slot in slots or any(offset < end and start < offset + length for start, end in bounds):
            raise ValueError('Duplicate/overlapping signature blobs')
        slots.add(slot)
        bounds.append((offset, offset + length))
        if slot == 0:
            if blob_magic != 0xfade0c02 or length < 44:
                raise ValueError('Invalid CodeDirectory')
            code_directory = True
        if slot == 5:
            if entitlements is not None or blob_magic != 0xfade7171:
                raise ValueError('Invalid/duplicate XML entitlement slot')
            entitlements = plistlib.loads(blob[8:].rstrip(b'\0'))
            if not isinstance(entitlements, dict):
                raise ValueError('Entitlements must be a dictionary')
    if not code_directory:
        raise ValueError('Missing CodeDirectory')
    return entitlements


def inspect_slice(data):
    if data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected little-endian 64-bit Mach-O')
    _, cpu, subtype, filetype, ncmds, sizeofcmds, flags, _ = struct.unpack('<8I', region(data, 0, 32))
    if cpu != 0x100000c or ncmds > 4096:
        raise ValueError('Unsupported Mach-O CPU/command count')
    subtype &= 0xffffff
    arch = {0: 'arm64', 2: 'arm64e'}.get(subtype, f'arm64-subtype-{subtype}')
    commands_end = 32 + sizeofcmds
    region(data, 0, commands_end)
    cursor = 32
    dependencies = []
    minimum = None
    platform = None
    signature = None
    entitlements = None
    for _ in range(ncmds):
        command, size = struct.unpack('<II', region(data, cursor, 8))
        if size < 8 or size % 4 or cursor + size > commands_end:
            raise ValueError('Invalid Mach-O load command')
        block = region(data, cursor, size)
        if command in (0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023):
            if size < 24:
                raise ValueError('Short dylib command')
            name_offset = struct.unpack_from('<I', block, 8)[0]
            if not 24 <= name_offset < size or b'\0' not in block[name_offset:]:
                raise ValueError('Invalid dependency name')
            dependencies.append(block[name_offset:].split(b'\0', 1)[0].decode('utf-8'))
        elif command == 0x25:
            if size < 16:
                raise ValueError('Short minimum-version command')
            minimum = struct.unpack_from('<I', block, 8)[0]
            platform = 2
        elif command == 0x32:
            if size < 24:
                raise ValueError('Short build-version command')
            platform, minimum = struct.unpack_from('<II', block, 8)
        elif command == 0x1d:
            if size != 16 or signature is not None:
                raise ValueError('Invalid/duplicate signature command')
            offset, length = struct.unpack_from('<II', block, 8)
            if offset < commands_end:
                raise ValueError('Signature overlaps Mach-O header')
            signature = (offset, length)
        cursor += size
    if cursor != commands_end:
        raise ValueError('Load command count/size mismatch')
    if signature is not None:
        entitlements = signature_entitlements(region(data, *signature))
    return {'arch': arch, 'cpu': cpu, 'subtype': subtype, 'filetype': filetype,
            'minimum': minimum, 'platform': platform, 'flags': flags,
            'dependencies': dependencies, 'signature_present': signature is not None,
            'entitlements': entitlements}
