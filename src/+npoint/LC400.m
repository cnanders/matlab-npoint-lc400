classdef LC400 < npoint.AbstractLC400
    
    
    
    % Several methods below have a paramater cDataType that indicates the
    % type of data being read from or written to the hardware.  Different
    % types have different formats:
    % Memory address        32-bit big endian hex format
    % Floats (f)            32-bit IEEE.754 hex format 
    % Integers (i)          int32 [-2^31 : 2^31 - 1] 32-bit big endian hex format
    % Unsigned ints (u)     uint32 [0 : 2^32 - 1] 32-bit big endian hex format
    
    
    % A note about signed integers with negative values.  MATLAB uses
    % so-called two's complement formatting for signed ints. 
    % https://en.wikipedia.org/wiki/Two%27s_complement.  
    % 
    % A simple example.  Assume uint3.  This has integer values in [0 - 7]
    % [0 0 0] = 0
    % [1 1 1] = 1 + 2 + 4 = 7
    % range = [0 : 2^3 - 1]
    %
    % If we now have int3, the range is [-4 : 3] or [-2^2 : 2^2 - 1]
    % Here is how binary values map to integer values
    % 000 = 0
    % 001 = 1
    % 010 = 2
    % 011 = 3
    % 100 = -4 (4 when unsigned)
    % 101 = -3 (5 when unsigned)
    % 110 = -2 (6 when unsigned)
    % 111 = -1 (7 when unsigned)
    %
    % Now imagine that you cast an int2 as an int3.  The range of an int2
    % is [-2^1 : 2^1 - 1] === [-2 : 1]
    % Here is how the binary values map to the integer values
    % 000 = 0
    % 001 = 1
    % 010 = OUT OF RANGE
    % 011 = OUT OF RANGE
    % 100 = OUT OF RANGE
    % 101 = OUT OF RANGE
    % 110 = -2 
    % 111 = -1 
    % 
    % Bottom line is when casting a signed binary into a higher-range
    % signed binary, there will be a lots of unused binary values in the
    % middle of the unsigned range of values.
        
    properties (Constant)
        
        
        addrCh1Base = '11831000'
        addrCh2Base = '11832000'
        
        addrCh1WavetableBase = 'C0000000'
        addrCh2WavetableBase = 'C0054000'
       
        % Recording
        addrNumSamplesToRecord = '1183036C'
        addrStartRecording = '11830374'
        addrRecordingDivisor = '118300F4'
        addrRecordPointer1 = '1183037C'
        addrRecordPointer2 = '11830380'
        addrRecordPointer3 = '11830384'
        addrRecordPointer4 = '11830388'
        addrRecordPointer5 = '1183038C'
        addrRecordPointer6 = '11830390'
        addrRecordPointer7 = '11830394'
        addrRecordPointer8 = '11830398'
        addrRecordBuffer1 = 'C03F0000'
        addrRecordBuffer2 = 'C0444000'
        addrRecordBuffer3 = 'C0498000'
        addrRecordBuffer4 = 'C04EC000'
        addrRecordBuffer5 = 'C0540000'
        addrRecordBuffer6 = 'C0594000'
        addrRecordBuffer7 = 'C05E8000'
        addrRecordBuffer8 = 'C063C000'

        offsetRange = '78'
        offsetRangeType = '44'
        offsetServoState = '84'
        offsetControlLoopInput = '404'
        offsetInverseDigitalScaleFactor = '230' % float
        offsetDigitalPositionCmd = '218'
        offsetDigitalSensorReading = '334'
        
        offsetWavetableEnable = '1F4'
        offsetWavetableIndex = '1F8'
        offsetWavetableEndIndex = '204'
        offsetWavetableCycleDelay = '200'
        offsetWavetableActive = '208'
        
        offsetProportionalGain = '720'
        offsetIntegralGain = '728'
        offsetDerivativeGain = '730'
        
        cCONNECTION_RS232 = 'rs232'
        cCONNECTION_TCPIP = 'tcpip';
        cCONNECTION_TCPCLIENT = 'tcpclient'
        
                
    end
    
    properties
        
        % {serial 1x1}
        s
       
        % {char 1xm} cCONNECTION_TCPIP or cCONNECTION_RS232
        cConnection
       
        % {char 1xm} port of MATLAB {serial}
        % In Terminal, run ls  -l /dev/{tty,cu}.* to see a list of all
        % available Serial Ports (they will all be virtual)
        cPort = '/dev/tty.usbserial-7440002A'

        % {char 1xm} terimator of MATLAB {serial}. Must match hardware
        cTerminator = 'CR'  % 'CR/LF'

        % {uint16 1x1} - baud rate of MATLAB {serial}.  Must match hardware
        u16BaudRate = uint16(57600);
        
        u16InputBufferSize = uint16(2^15);
        u16OutputBufferSize = uint16(2^15);

        % {double 1x1} - timeout of MATLAB {serial} - amount of time it will
        % wait for a response before aborting.  
        dTimeout = 10;
        
        lShowWaitingForBytes = false;
        
        % {char 1xm} tcp/ip host
        cTcpipHost = '192.168.0.2'
        
        % {uint16 1x1} tcpip port network control uses telnet port 23
        u16TcpipPort = uint16(23)
        
        dTimeoutSeconds = 1;
       
    end
    properties (Access = private)
        
        % {logical 1x1} true whend doing a long read. Causes other read
        % commands to not communicate with hardware and return bogus value
        lBusy = false
        
    end
    
    methods 
        
        function this = LC400(varargin) 
            
            % Default connection
            this.cConnection = this.cCONNECTION_RS232;
            
            for k = 1 : 2: length(varargin)
                this.msg(sprintf('passed in %s', varargin{k}));
                if this.hasProp( varargin{k})
                    this.msg(sprintf('settting %s', varargin{k}));
                    this.(varargin{k}) = varargin{k + 1};
                end
            end
            
            this.init();
            this.connect();
            
        end
        
         function delete(this)
            this.msg('delete() calling disconnect()');
            this.disconnect();
        end
                
        % @param {uint8 1x1} channel
        function l = getWavetableActive(this, u8Ch)
            
            if this.lBusy
                l = false;
                return;
            end
            
            import hex.HexUtils
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), this.offsetWavetableActive);
            
            try
            [u32, lSuccess] = this.readSingle(cAddr, 'uint32');
            if ~lSuccess
                l = false;
            else
                l = logical(u32);
            end
            
            catch mE
                l = false;
                fprintf('npoint.LC400.getWavetableActive readSingle problem\n');
            end
            

        end
        
        % See recordRaw().  Difference here is returned values are {double}
        % and are mechanical tilt of stage in real units (um, mrad, etc). 
        %
        % Need to cast i32 returned from Java as a double before the
        % multiplication because in matlab when you multipley i32 by a
        % double it stays an i32 and since the return will be between
        % -10 and 10 it would only be integers
        %
        % 2013.08.27 adding the digital scale factor, which is the ratio
        % between the open loop range of the stage and the closed loop
        % range.  When you record data from the 'input' register, it
        % needs to be scaled by the inverse of the digital scale factor
        % to convert back to real world units.  The sensor output
        % register already has the inverse digital scale factor applied.
        %
        % @param {uint32) u32Num - number of samples @ 24us clock
        % @return {double 4 x u32Num} dData - tilt of stage in radians
        
        function d = record(this, u32Num)
            
            this.lBusy = true;
            i32Raw = this.recordRaw(u32Num);
            this.lBusy = false;
            
            dRaw = double(i32Raw);
            max(dRaw(1, :))
            min(dRaw(1, :))
            dMax = (2^20 - 2)/2;
            dRelative = dRaw / dMax;
            d = dRelative ; % * double(this.getRange(1)) convert to radians
            
            % Channel 1 and 2 command signals need to be scaled by inverse
            % of the digital scale factor.
            d(1, :) = d(1, :) * this.getInverseDigitalScaleFactor(uint8(1));
            d(3, :) = d(3, :) * this.getInverseDigitalScaleFactor(uint8(2));
        end
        
        % @param {uint8 1x1} channel 
        % @param {int32 1xm} 20-bit values in [-524287 : +524287]
        % Get this by multiplying the relative signal (in [-1 : 1]) by 
        % (2^20 - 2)/2 === 524287 and rounding the result to nearest int. 
        function setWavetable(this, u8Ch, i32Vals)
            
            import hex.HexUtils
            
            [dRows, dCols] = size(i32Vals);
            if dCols > 1
                this.msg('setWavetable() MUST pass in size (nx1) not (1xn) array');
            end
            
            % Write wavetable            
            cAddr = this.getBaseWaveAddr(u8Ch);
            this.writeArrayLong(cAddr, i32Vals);
            
            % Set end of wavetable index.
            % Needs to be length - 1
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), this.offsetWavetableEndIndex);
            this.writeSingle(cAddr, uint32(length(i32Vals) - 1));
        
        end
        
        % @param {uint8 1x1} channel 
        function u32 = getEndIndexOfWavetable(this, u8Ch)
            u32 = 0; % default
            
            if this.lBusy
                u32 = 0;
                return;
            end
            
            import hex.HexUtils
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), this.offsetWavetableEndIndex);
            
            [u32, lSuccess] = this.readSingle(cAddr, 'uint32');
                
            if ~lSuccess
                u32 = 0;
            end 
        end
        
        
        function i20 = getWavetables(this, u32Num)
            
            if this.lBusy
                i20 = zeros(2, u32Num);
                return;
            end
                
            this.lBusy = true;
            
            i20Ch1 = this.readArrayLong(this.addrCh1WavetableBase, u32Num, 'int32');
            i20Ch2 = this.readArrayLong(this.addrCh2WavetableBase, u32Num, 'int32');
            
            this.lBusy = false;
            
            i20 = zeros(2, u32Num);
            
            i20(1, :) = i20Ch1;
            i20(2, :) = i20Ch2;
                        
        end
        
        % @param {uint8 1x1} channel
        % @param {logical 1x1} 
        function setWavetableEnable(this, u8Ch, l)
            import hex.HexUtils
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), this.offsetWavetableEnable);
            this.writeSingle(cAddr, uint8(l));
        end
        
        
        % Enable/disable both channels simultaneously
        % @param {logical 1x1} true to enable
        function setTwoWavetablesActive(this, l) 
            
            this.msg('setTwoWavetablesActive()');
            
            import hex.HexUtils
            
            
            % Set "Wavetable Index" to zero for both channels prior
            % to restarting the waveform
            
            cAddr1 = HexUtils.add(this.addrCh1Base, this.offsetWavetableIndex);
            cAddr2 = HexUtils.add(this.addrCh2Base, this.offsetWavetableIndex);
            
            this.writeSingle(cAddr1, uint8(0));
            this.writeSingle(cAddr2, uint8(0));
            
            % Set both to active
            
            % OLD
            %{
            cAddr = HexUtils.add(this.addrCh1Base, this.offsetWavetableActive);
            this.writeSingle(cAddr, uint8(l));
            
            cAddr = HexUtils.add(this.addrCh2Base, this.offsetWavetableActive);
            this.writeSingle(cAddr, uint8(l));
            %}
            
            % NEW
            % Use a single write stream with both commands so they are
            % processed on same clock cycle on the LC400
            
            cAddr1Hex = HexUtils.add(this.addrCh1Base, this.offsetWavetableActive);
            cAddr2Hex = HexUtils.add(this.addrCh2Base, this.offsetWavetableActive);
            
            cAddr1HexLE = HexUtils.changeEndianness32(cAddr1Hex);
            cAddr2HexLE = HexUtils.changeEndianness32(cAddr2Hex);
            
            cValHex = this.castToHex32(uint32(l));
            cValHexLE = HexUtils.changeEndianness32(cValHex);

            % Create commnad string

            cCmdHex = 'A2';
            cStopHex = '55';

            cDataHex = [...
                cCmdHex cAddr1HexLE cValHexLE cStopHex ...
                cCmdHex cAddr2HexLE cValHexLE cStopHex];

            % Convert to a column list of hex bytes
            % 1-byte start
            % 4-bytes address litte endian
            % 4-bytes value little endian
            % 1-byte end
            L = length(cDataHex);
            cDataHex = reshape(cDataHex, 2, L/2)';

            % Convert each byte from hex representation to int
            % representation
            dDataInt = hex2dec(cDataHex);

            % Issue command
            
            this.write(dDataInt);
            
        end
        
       
        
        
    end
    
    methods (Access = protected)
        
        
        function init(this)
            
            fprintf('npoint.LC400.init() \n');
            switch this.cConnection
                case this.cCONNECTION_RS232
                    this.s = serial(this.cPort);    
                    st = get(this.s,'Status');
                    % cannot open a port a second time
                    if(st(1) == 'o')
                        fclose(this.s);
                    end

                    this.s.BaudRate = this.u16BaudRate;
                    this.s.InputBufferSize = this.u16InputBufferSize;
                    this.s.OutputBufferSize = this.u16OutputBufferSize;
                case this.cCONNECTION_TCPIP
                    
                    
                    this.s = tcpip(this.cTcpipHost, this.u16TcpipPort);
                    % this.s.BaudRate = this.u16BaudRate;
                    this.s.InputBufferSize = this.u16InputBufferSize;
                    this.s.OutputBufferSize = this.u16OutputBufferSize;
                    
                    % Don't use Nagle's algorithm; send data
                    % immediately to the newtork
                    this.s.TransferDelay = 'off';
                   
                case this.cCONNECTION_TCPCLIENT
                    
                    this.s = tcpclient(this.cTcpipHost, this.u16TcpipPort, ...
                        'Timeout', this.dTimeoutSeconds ...
                    );
                    
            end
        end
        
        
        % Return the base address of a channel
        % @param {uint8 1x1} u8Ch - channel
        % @return {char 1x8} 8-char hex string  (32-bit)
        function c = getBaseAddr(this, u8Ch)
            switch u8Ch
                case 1
                    c = this.addrCh1Base;
                case 2
                    c = this.addrCh2Base;
            end
            
        end
        
        % Return the base wavetable address of a channel
        % @param {uint8 1x1} u8Ch - channel
        % @return {char 1x8} 8-char hex string  (32-bit)
        function c = getBaseWaveAddr(this, u8Ch)
            switch u8Ch
                case 1
                    c = this.addrCh1WavetableBase;
                case 2
                    c = this.addrCh2WavetableBase;
            end
            
        end

        
        
        
        function clearBytesAvailable(this)
            
            this.lBusy = true;
            % This doesn't alway work.  I've found that if I overfill the
            % input buffer, call this method, then do a subsequent read,
            % the results come back all with -1.6050e9.  Need to figure
            % this out
            
            this.msg('clearBytesAvailable()');
            
            while this.s.BytesAvailable > 0
                cMsg = sprintf(...
                    'clearBytesAvailable() clearing %1.0f bytes', ...
                    this.s.BytesAvailable ...
                );
                this.msg(cMsg);
                this.read()
                
            end
            
            this.lBusy = false;
        end
        
        function connect(this)
            
            fprintf('npoint.LC400.connect() \n');
            switch this.cConnection
                case {this.cCONNECTION_TCPIP, this.cCONNECTION_RS232}
                    this.msg('connect()');
                    try
                        fopen(this.s); 
                    catch ME
                        
                         % Will crash the app, but gives lovely stack trace.
                        error(getReport(mE));

                    end

                    
                case this.cCONNECTION_TCPCLIENT
                    % do nothing
            end
            
            this.clearBytesAvailable();
        end
        
        function disconnect(this)
            
            fprintf('npoint.LC400.disconnect()\n');
            switch this.cConnection
                case {this.cCONNECTION_TCPIP, this.cCONNECTION_RS232}
                    this.msg('disconnect()');
                    try
                        fclose(this.s);
                    catch ME
                         % Will crash the app, but gives lovely stack trace.
                         error(getReport(mE));
                    end
                 case this.cCONNECTION_TCPCLIENT
                    % do nothing
                    this.s = [];
            end
                    
        end
        

        
        
        function d = getInverseDigitalScaleFactor(this, u8Ch)
           
           
           if this.lBusy
               d = 1;
               return;
           end
           
           import hex.HexUtils
           cAddr = HexUtils.add(this.getBaseAddr(u8Ch), this.offsetInverseDigitalScaleFactor );
           [d, lSuccess] = this.readSingle(cAddr, 'float');
           
           if ~lSuccess
               d = 1;
           end
            
        end
        
        
        % @param {uint8 1x1} channel
        function l = getWavetableEnable(this, u8Ch)
            
            if this.lBusy
                l = false;
                return;
            end
            
            import hex.HexUtils
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), this.offsetWavetableEnable);
            [u32, lSuccess] = this.readSingle(cAddr, 'uint32');
            if ~lSuccess
                l = false;
            else
                l = logical(u32);
            end
            
        end
        
        
        
        % @param {uint8 1x1} u8Ch - channel
        % @param {char 1x1} cProp - PID property. Supported values
        % this.GAIN_PROPORTIONAL
        % this.GAIN_INTEGRAL
        % this.GAIN_DIFFERENTIAL
        function d = getGain(this, u8Ch, cProp)
            
            if this.lBusy
                d = 0;
                return;
            end
            
            
            import hex.HexUtils
            switch cProp
                case this.GAIN_PROPORTIONAL
                    cOffset = this.offsetProportionalGain;
                case this.GAIN_INTEGRAL
                    cOffset = this.offsetIntegralGain;
                case this.GAIN_DIFFERENTIAL
                    cOffset = this.offsetDifferentialGain;
            end
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), cOffset);
            [d, lSuccess] = this.readSingle(cAddr, 'float');
            
            if ~lSuccess
                d = 0;
            end
            
            
        end
        
        % @param {uint8 1x1} channel
        function l = getServoState(this, u8Ch)
            l = true;
        end
        
        % @param {uint8 1x1} channel
        % @param {char 1xm} cProp - supported values:
        % this.ANALOG_SCALE
        % this.DIGITAL_SCALE
        % this.DIGITAL_SCALE_INV
        % this.MONITOR_SCALE
        function d = getFloatValueFromString(this, u8Ch, cProp)
            
            if this.lBusy
                d = 0;
                return;
            end
            
            import hex.HexUtils
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), cHexOffset);
            [d, lSuccess] = this.readSingle(cAddr, 'f');
            
            if ~lSuccess
                d = 0;
            end
            
        end
        
        % @param {uint8 1x1} channel
        % @param {char 1xm} supported values:
        % this.ANALOG_OFFSET
        % this.DIGITAL_OFFSET
        % this.MONITOR_OFFSET
        function i32 = getIntValueFromString(this, u8Ch, cProp)
            i32 = int32(0);
        end
        
        
        
        
        
        % @param {uint8 1x1} channel
        % @return {double 1x1} - the range of the stage.  The range
        % parameter can be used to convert from microns to 20 bit counts
        % (the controller uses 20 bit digitized values rather than distance
        % units for internal calculations).� For example if the range is
        % 277 microns: 1,048,575 20 bit counts divided by 277 = 3,785.47
        % "counts per micron".
        function d = getRange(this, u8Ch)
            
            if this.lBusy
                d = 0;
                return;
            end
            import hex.HexUtils
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), this.offsetRange);
            [d, lSuccess] = this.readSingle(cAddr, 'uint32');
            
            if ~lSuccess
                d = 0;
            end
        end
        
        
        % @param {uint8 1x1} channel
        % @param {char 1x1} supported values
        % this.GAIN_PROPORTIONAL
        % this.GAIN_INTEGRAL
        % this.GAIN_DIFFERENTIAL
        function setGain(this, u8Ch, cProp, dVal)
        
        end
        
        
        
        
        
        % @param {uint8 1x1} channel
        % @param {logical 1x1} 
        function setWavetableActive(this, u8Ch, l)
            import hex.HexUtils
            cAddr = HexUtils.add(this.getBaseAddr(u8Ch), this.offsetWavetableActive);
            this.writeSingle(cAddr, uint8(l));
        end
        
        
        
        % Record ch1 and ch2 command value and sensor value for a specified
        % number of clock cycles.  The clock is 24 us (one sample per 24 us).
        % Max is two seconds worth of data or 83333 samples.
        % @param {uint32) u32Num - number of samples @ 24us clock
        % @return {int32 4 x u32Num} i32Data - output data. Read below
        % for scaling. See record() for data returned in radians
        %
        % Notes
        %
        % i32Data(1, :) - ch 1 command
        % i32Data(2, :) - ch 1 sensor
        % i32Data(3, :) - ch 2 command
        % i32Data(4, :) - ch 2 sensor
        % Range of values is +/- 2^20/2 even though data type is i32  
        % +2^20/2 is +3 mrad mechanical tilt
        % -2^20/2 is -3 mrad mechanical tilt
        
        
        function i32 = recordRaw(this, u32Num)
            
            % Default return
            i32 = zeros(4, u32Num);
            
            import hex.HexUtils
            
            try
                % Set number of samples to record
                this.writeSingle(...
                    this.addrNumSamplesToRecord, ...
                    u32Num ...
                );

                % Set record pointers
                % Ch 1 command
                this.writeSingle(...
                    this.addrRecordPointer1, ...
                    HexUtils.add(this.addrCh1Base, this.offsetControlLoopInput) ...
                );
                % Ch 1 sensor
                this.writeSingle(...
                    this.addrRecordPointer2, ...
                    HexUtils.add(this.addrCh1Base, this.offsetDigitalSensorReading) ...
                );

                % Ch 2 command
                this.writeSingle(...
                    this.addrRecordPointer3, ...
                    HexUtils.add(this.addrCh2Base, this.offsetControlLoopInput) ...
                );
                % Ch 2 sensor
                this.writeSingle(...
                    this.addrRecordPointer4, ...
                    HexUtils.add(this.addrCh2Base, this.offsetDigitalSensorReading) ...
                ); 


                % Set number of clock cycles per sample.  When you set this to
                % 1, you get every sample.  If you set it to two, you grab
                % every other, etc.  This is a way to downsample, if desired.
                % Not going to implmeent it here.

                this.writeSingle(...
                    this.addrRecordingDivisor, ...
                    uint8(1) ...
                );

                % Start the recording 
                this.writeSingle(...
                    this.addrStartRecording, ...
                    uint8(1) ...
                );

                this.waitForRecordingComplete();

                % Read the record buffers

                i32Ch1Command = this.readArrayLong(...
                    this.addrRecordBuffer1, ...
                    u32Num, ...
                    'int32' ...
                );

                i32Ch1Sensor = this.readArrayLong(...
                    this.addrRecordBuffer2, ...
                    u32Num, ...
                    'int32' ...
                );

                i32Ch2Command = this.readArrayLong(...
                    this.addrRecordBuffer3, ...
                    u32Num, ...
                    'int32' ...
                );
                i32Ch2Sensor = this.readArrayLong(...
                    this.addrRecordBuffer4, ...
                    u32Num, ...
                    'int32' ...
                );


                % i32Ch1Command = this.readArrayLong(this.getBaseWaveAddr(1), u32Num, 'int20');
                % i32Ch2Command = this.readArrayLong(this.getBaseWaveAddr(2), u32Num, 'int20');

                % Int values > 2^19 represent negative stage position.  
                % (Two's complement for 20-bit)
                % Largest negative stage position represented by 2^19 + 1

                %{
                idx = find(d > 2^19);
                d(idx) = -(2^19 - d(idx));
                %}

                
                i32(1, :) = i32Ch1Command; % ch 1 command
                i32(2, :) = i32Ch1Sensor;
                i32(3, :) = i32Ch2Command; % ch 2 command
                i32(4, :) = i32Ch2Sensor;
            catch mE
                
            end
            
                
                
            
        end
        
        function waitForRecordingComplete(this)
                    
            u32Recording = 1;
            
            while  u32Recording ~= 0 
                [u32Recording, lSuccess] = this.readSingle(...
                        this.addrStartRecording, ...
                        'uint32' ...
                    );
                % Still recording ...
                
            end
            
            % setInteger(Addresses.recordingDivisor, 0) 'set recording
            % divisor for samples every 24 �sec - standard nPControl PC
            % software version 1.2.7 and earlier assumes 24 microsecond
            % interval
                
            
        end
        
        
        
        
        % Reads a list of addresses.  It works by looping through each
        % address and issuing the "read single" command.  Then it waits
        % until serial.BytesAvailable reaches the expected value (each
        % "read single" returns 10 bytes (start (1) address (4) data (4)
        % stop (1)).  Then it issues a single ffread() to pull all of the
        % returned data from input buffer of the serial.  It then
        % unpacks the returned byte stream, distinguishing the data from
        % each read command, and then converts each read to float, int, or
        % uint based on the type flag passed in. 
        %
        % Be advised that the input buffer of the MATLAB serial has a
        % finite size and can fill up.  I think the default is 512 bytes
        % which is 51 "read single" commands
        % 
        % @param {char mx8} addr - list of memory addresses as 32-bit (4-byte) hex strings
        % (eight hex characters), i.e.,
        %   1183207C
        %   1183208A
        %   created by ['1183207C';'1183208A']
        % @param {char 1xm} type (see top of class)


        function [str, lSuccess] = readSingle(this, addr, type)
       
            [m,n] = size(addr);
            
            % Loop through addresses, issue read command for each.
            for j=1:m
                
                % Generate command string in big endian format
                % [start-byte][4-byte memory address][stop-byte]
                % 'A0' is the read 32-bit val from address command
                % '55' is stop byte
                cmdstr = ['A0' addr(j,:) '55'];
                
                % Convert 4-byte memory address to least significant byte
                % (LSB) first 
                cmdstr = cmdstr([1 2 9 10 7 8 5 6 3 4 11 12]);
                
                % Convert to a column list of six 2-hex-char bytes {char 6x2} 
                % first row is start byte, last row is stop byte, middle
                % rows are address in little endian order. 
                %   start byte
                %   least significant byte
                %   more significant byte
                %   even more significant byte
                %   most significant byte
                %   stop byte
                
                L = length(cmdstr);
                c = reshape(cmdstr,2,L/2)';
                
                % Convert each 2-characer hex byte to a double to get a
                % {double 6x1} 
                d = hex2dec(c);
                
                % Write the command to serial
                this.write(d)
                
                
                
            end
            
            % Have now issued read commands for all addresses
            % provided.
            
            % Go into a loop and wait for the serial port to return the
            % expected number of bytes available (or timeout, which ever
            % occurs first).  With the virtual COM port and MATLAB
            % overhead, it will invariably take different amounts of time
            % for the serial to see the expected BytesAvailable
            
            dBytesExpected = m * 10;
            lSuccess = this.waitForBytesExpected(dBytesExpected);
            
            if ~lSuccess
                str = '';
                return;
            end
            
            dResponse = this.read();
            str = this.unpackMultiSinglefread(dResponse, m, type);
            
        end
        
        % Returns true if expected number of bytes showed up in
        % BytesAvailable before the timeout, false otherwise
        function lSuccess = waitForBytesExpected(this, dBytesExpected)
            
            if this.lShowWaitingForBytes
                cMsg = sprintf(...
                    'waitForBytesExpected(%1.0f)', ...
                    dBytesExpected ...
                );
                this.msg(cMsg);
            end
            
            % Reset so can track time waiting in the while loop
            tic
            
            while this.s.BytesAvailable < dBytesExpected
                
                if this.lShowWaitingForBytes
                    cMsg = sprintf(...
                        'Waiting ... %1.0f of %1.0f expected bytes are currently available', ...
                        this.s.BytesAvailable, ...
                        dBytesExpected ...
                    );
                    this.msg(cMsg);
                end
                
                if (toc > this.dTimeout)
                    cMsg = sprintf(...
                        'Error.  Serial took too long (> %1.1f sec) to reach expected %1.0f BytesAvailable %1.0f', ...
                        this.dTimeout, ...
                        dBytesExpected ...
                    );
                    % error(cMsg);
                    lSuccess = false; 
                    return;
                end
                
                % pause(0.1);
            end
            
            cMsg = sprintf(...
                'Waited %1.0 ms for %1.0f of %1.0f expected bytes', ...
                toc & 1000, ...
                dBytesExpected ...
            );
            this.msg(cMsg);
            lSuccess = true;
            
        end
        
        % @param {char mx8} cAddrHex32 - start addresses as 32-bit (4-byte)
        %   big endian hex string
        % @param {uint32 1x1} u32Num - number of reads
        % @param {cType 1x1} cType - all data must be same type

        function [d, lSuccess] = readArray(this, cAddrHex32, u32Num, cType)
            
            
            % Default return
            d = zeros(1, u32Num);
            
            import hex.HexUtils
            
            % Convert address to little endian
            cAddrHex32 = HexUtils.changeEndianness32(cAddrHex32);
            
            % Convert num reads to 32-bit hex.  The trick to doing this is
            % to add the result of hex2dec to '00000000', so we get a full
            % 32-bit hex string for the number of reads
            cNumHex32 = dec2hex(u32Num, 8);
            
            % Make little endian
            cNumHex32 = HexUtils.changeEndianness32(cNumHex32);
            
            
            cCmdHex = 'A4';
            cStopHex = '55';
            
            % Generate command string
            cDataHex = [cCmdHex cAddrHex32 cNumHex32 cStopHex];
            
            % Convert to a column list of 1-byte hex strings {char 2x10}
            cDataHex = reshape(cDataHex, 2, length(cDataHex)/2)';
                        
            % Confert 1-byte hex strings in to double {double 1x10} for
            % transmission
            dDataInt = hex2dec(cDataHex);
             
            
            % Write the command to serial
            this.write(dDataInt);
                                    
            % Wait for expected number of bytes to be available
            dBytesExpected = 1 + 4 + 4 * u32Num + 1;
            
            lSuccess = this.waitForBytesExpected(dBytesExpected);
            
            if ~lSuccess
                return;
            end
            
            % Read the result
            tic
            
            dResponse = this.read();
                        
            
            dTimeElapsed = toc;
            cMsg = sprintf('readArray() read elapsed time: %1.1f ms', dTimeElapsed * 1000);
            % this.msg(cMsg);
            
            % Unpack the result
            tic 
            d = this.unpackArrayfread(dResponse, cType);
            dTimeElapsed = toc;
            cMsg = sprintf('readArray() unpack elapsed time: %1.1f ms', dTimeElapsed * 1000);
            % this.msg(cMsg);
            
            lSuccess = true;
            
        end
        
        
        % Unpack the response of a read on the serial after issuing one
        % (or multiple) "read single" commands and 
        % @param {double dNum*10x1} - dResponse - response of a read on the serial
        %   after issuing one (or multiple) "read single" commands.  Each
        %   byte of the response is represented as a double after read.
        % @param {uint32 1x1} u32Num - number of "read single" commands that were
        %   issued prior to read
        % @param {char 1xu32Num} cType 
        
        
        function str = unpackMultiSinglefread(this, dResponse, u32Num, type)
            
                        
            % The response of a single read command is a {double 10x1} 
            % with one double per byte.  The values are 8-bit int, but data
            % type is double
            %
            % [start-byte]
            % [ ...
            %   ... 4-byte memory address little endian 
            %   ...
            %   ... ]
            % [ ...
            %   ... 4-byte value little endian
            %   ...
            %   ... ]
            % [stop-byte]
            % 
            % And each one is in base10 not base16.
            %
            % If m read commands were issued before reading the output
            % buffer, the response will be a {m*10 x 1} concatenated set of
            % single read responses.
            
            % Reshape response into a {double 10xm} where each column 
            % contains a single response:
            %
            % For example, if the same address is read twice we desire to
            % reshape the response like this:
            %
            %   160   160   Start byte
            %   ---   ---
            %   120   120   4-byte address little endian
            %    16    16
            %   131   131
            %    17    17
            %   ---   ---
            %     6     6   4-byte data little endian
            %     0     0
            %     0     0
            %     0     0
            %   ---   ---
            %    85    85   Stop byte
            
            
            k = reshape(dResponse, 10, u32Num);
            
            % -- reorder the bytes --
            % Convert 4-byte address and 4-byte data of each response to
            % big endian.  This operaion simultaneously works on all
            % columns.            
            
            k = k([1 5 4 3 2 9 8 7 6 10],:);
            
            % This says: "row 1 stays row 1", 
            % "row 5 becomes row 2", 
            % "row 4 becomes row 2", etc.
            
            
            % Loop through all columns (each col has the response of a single
            % read command
            
            for j = 1:u32Num
                
                s = k(:,j);
                
                % Convert each 1-byte int to hex representation
                % (force two hex characters for each)
                s = dec2hex(s, 2);
                
                % Concate the big endian response into a {char 1x20}
                s = reshape(s',1, 20);
                
                % Grab the eight hex characters of data (32-bit)
                s = s(11:18);
                
                % Based on the type of data being read, convert the hex
                % string to float, int, or uint (or leave as hex)
                str(j, :) = this.convertHex32(s, type(j, :));    
            end
            
            
        end
        
        % @param {double ?x1} response of read
        % @param {char 1x1} cDataType 
        
        function d = unpackArrayfread(this, dResponse, cDataType)
         
            
            % The response of a "read array" command is a {double (1 + 4 + 4*numReads + 1)x1} 
            % with one double per byte:
            %
            % [start-byte]
            % [ ...
            %   ... 4-byte memory start address little endian 
            %   ...
            %   ... ]
            % [ ...
            %   ... 4-byte value little endian
            %   ...
            %   ... ]
            % [ ...
            %   ... 4-byte value little endian
            %   ...
            %   ... ]
            % [ ...
            %   ... 4-byte value little endian
            %   ...
            %   ... ]
            % ...
            % ...
            % [stop-byte]
            
            % Remove the followign elements leaving only data:
            % 1 (start byte)
            % 2-5 (start address)
            % last (end byte)
            
            dData = dResponse(6:end-1);
            
            % Reshape so each 4-byte data value is a column
            dNum = length(dData)/4;
            dData = reshape(dData, 4, dNum);
            
            % Convert each column from little endian to big endian
            dData = dData([4 3 2 1], :);
            
            % Convert each byte from integer format to 2-char hex format
            
            % OLD WAY
            % Do it in a loop.  No need.
            
            % NEW WAY 
            % More performant because it calls dec2hex one time instead of
            % in the for loop.  Next speed improvement will be to
            % parallelize hex32ToNum.  BE ADVISED: dec2hex returns a {char
            % dNum*4x2} (list of 2-char hex bytes) It does not preserve
            % original size.  Need to reshape after
            
            cHexData = dec2hex(dData, 2);
            
            % Reshape the data so each row is an 32-bit hex (8-char) string
            % representing the value of one read.  There is a file in this
            % directory called reshape_test that shows how reshape works.
            % Need to do some transposing to get it to do what we want.
            
            cHexData = reshape(cHexData', 8, dNum)';
            
            % Convert each 32-bit hex to desired representation based on
            % data type
            
            d = this.convertHex32(cHexData, cDataType);
            
            return;
            
            % OLD WAY
                         
            d = zeros(1, dNum);
            for n = 1 : dNum
                %{
                rowStart = 1 + (n - 1) * 4;
                rowStop = n * 4;
                cHexVal = cHexData(rowStart : rowStop, :);
                cHexVal = reshape(cHexVal', 1, 8);
                %}
                
                cHexVal = cHexData(n, :);
                
                % Based on the type of data that was read, the 32-bit hex
                % string could be formatted in IEEE.754 or big endian.
                
                % Convert 32-bit hex string to specified type, if necessary
                d(n) = this.convertHex32(cHexVal, cDataType);
            end
            
        end
        
        

        % @param {char mx8} addr - list of memory addresses as big endian hex strings, i.e.,
        %   11832078
        %   11832080
        %   created by ['11832078';'11832080']
        % @param {mx} values - list of values as big endian hex strings?
        % @param {char 1xm} types - type of each value.  Can be 'f', 'i',
        % 'u', 'h' (hex)

        
        function writeSingle(this, cAddrHex, xValues, cTypes)
            
            import hex.HexUtils
            
            % Loop through values, convert to hex representation (big
            % endian)
            
            [rows, cols] = size(cAddrHex);
            for n = 1 : rows
                
                cValHex = this.castToHex32(xValues(n, :));
                % cValHex = this.valToHex32(xValues(n, :), cTypes(n, :));
                                
                % Convert hex representation of value to little endian
                cValHexLE = HexUtils.changeEndianness32(cValHex);
                
                % Convert address to little endian
                cAddrHexLE = HexUtils.changeEndianness32(cAddrHex);
                
                % Create commnad string
                
                cCmdHex = 'A2';
                cStopHex = '55';
                
                cDataHex = [cCmdHex cAddrHexLE cValHexLE cStopHex];
                
                % Convert to a column list of 10 hex bytes
                % 1-byte start
                % 4-bytes address litte endian
                % 4-bytes value little endian
                % 1-byte end
                L = length(cDataHex);
                cDataHex = reshape(cDataHex, 2, L/2)';
                
                % Convert each byte from hex representation to int
                % representation
                dDataInt = hex2dec(cDataHex);
                                
                % Issue command
                this.write(dDataInt);
                
            end
        end
        
        
        % Wrapper around writeArray() for writes that are so big that they
        % would fill the output buffer if put into a single writeArray call
        
        function writeArrayLong(this, cAddrHex, xValues)
            
            import hex.HexUtils
            
            cMethod = 'writeArrayLong()';

            % Based on the size of the output buffer, there is a maximum
            % number of write + write next commands the output buffer can
            % support 
            %
            % The write stream contains 10 bytes
            %   one byte for command, 
            %   four bytes for start memory address,
            %   four bytes per value,
            %   one byte for stop
            % 
            % The write next stream contains 6 bytes
            %   one byte for command
            %   four bytes per value
            %   one byte for stop
            
            % To compute writes per writeArray(), subtract 10 from the
            % output buffer (for the original "write" command), divide the
            % result by 6 bytes per "write next", then add 1 back for the
            % original "write"
            
            switch this.cConnection
                case this.cCONNECTION_TCPCLIENT
                    dOutputBuffer = 2^15;
                otherwise
                    dOutputBuffer = this.s.OutputBuffer;
            end
            
            dNumMax = floor((dOutputBuffer - 10)/6) + 1;
                    
            cMsg = sprintf(...
                '%s s.OutputBuffer is %1.0f bytes ', ...
                cMethod,...
                dOutputBuffer ...
            );            
            this.msg(cMsg);

            cMsg = sprintf(...
                '%s Max writes of ouput buffer = %1.0f ', ...
                cMethod, ...
                dNumMax ...
            );            
            this.msg(cMsg);

            cMsg = sprintf(...
                '%s 10 bytes/write * 1 + 6 bytes/writenext * %1.0f = %1.0f bytes ', ...
                cMethod, ...
                dNumMax - 1, ...
                10 + (dNumMax - 1)*6 ...
            );            
            this.msg(cMsg);
                       
            dNumWriteArrays = ceil(length(xValues)/dNumMax);
            
            cMsg = sprintf(...
                '%s Requires %1.0f calls to writeArray()', ...
                cMethod, ...
                dNumWriteArrays ...
            );            
            this.msg(cMsg);
                        
            for n = 1 : dNumWriteArrays
                
                % Compute index of xValues
                if n < dNumWriteArrays
                    dNum = dNumMax;
                    dStart = 1 + (n - 1) * dNum;
                    dEnd = n * dNum;
                else
                    dNum = length(xValues) - (n - 1) * dNumMax;
                    dStart = 1 + (n - 1)*dNumMax;
                    dEnd = dStart + dNum - 1;
                end
                
                % With each call to writeArray, need to offset the start
                % memory address by 4 per value
                 
                dAddrOffset = (n - 1) * 4 * dNumMax;
                cAddr = HexUtils.add(cAddrHex, dec2hex(dAddrOffset));
                
                % Issue writeArray
                this.writeArray(cAddr, xValues(dStart: dEnd));
                
            end
            
            
            
        end
        
        
        % @param {char 1x8} cAddrHex
        % @param {mixed mx1} xValues - type can be: 
        % double, single (uses IEEE.754)
        % uint8, uint16, uint32,
        % int32
        
        function writeArray(this, cAddrHex, xValues)
            
            import hex.HexUtils
            
            % Loop through values, convert to hex representation (big
            % endian)
            
            cMsg = sprintf(...
                'writeArray() writing %1.0f values to %s...', ...
                length(xValues), ...
                cAddrHex ...
            );
        
            this.msg(cMsg);
            
            % Cast xValues to hex
            cValHex = this.castToHex32(xValues);
            % cValHex = this.valToHex32(xValues(n, :), cType);

            % Convert hex representation of value to little endian
            cValHexLE = HexUtils.changeEndianness32(cValHex);
            
            % Compute size of cDataInt.  
            % 10 bytes for first "write"
            % 6 bytes per additional "write next"
            cDataRows = 10 + (length(xValues) - 1) * 6;
            cDataFullInt = zeros(cDataRows, 1);
            
            [rows, cols] = size(xValues);
            for n = 1 : rows
                                
                if n == 1
                    % First write
                    
                    % Convert address to little endian
                    cAddrHexLE = HexUtils.changeEndianness32(cAddrHex);

                    % Create commnad string
                    cCmdHex = 'A2'; % write
                    cStopHex = '55';
                    cDataHex = [cCmdHex cAddrHexLE cValHexLE(n, :) cStopHex];
                    
                    
                else
                    % Write next (don't need address)
                
                    % Create commnad string
                    cCmdHex = 'A3'; % write next
                    cStopHex = '55';
                    cDataHex = [cCmdHex cValHexLE(n, :) cStopHex];
                    
                end
                
                % Convert to a column list of hex bytes:
                % (write first) 10 hex bytes OR
                % (write next) 6 hex bytes
                % 1-byte start
                % 4-bytes address litte endian (only on first)
                % 4-bytes value little endian
                % 1-byte end
                L = length(cDataHex);
                cDataHex = reshape(cDataHex, 2, L/2)';

                % Convert each byte from hex representation to int representation
                cDataInt = hex2dec(cDataHex);
                
                % OLD
                % Issue command for each 
                % this.write(cDataInt);
                
                % NEW
                % Combine into a single stream of "write" and "write next"
                % and issue command at the end
                
                if n == 1
                    dStart = 1;
                    dEnd = 10;
                    cDataFullInt(dStart : dEnd, 1) = cDataInt;
                else
                    dStart = 11 + (n - 2)*6;
                    dEnd = dStart + 5;
                    cDataFullInt(dStart : dEnd, 1) = cDataInt;
                end
                
            end
            this.write(cDataFullInt);
        end
        
        
        
        
        
        
        % TEST AREA
        
        % Unoptimized reads each 32-bit float with a separate command.
        
        %{
        function d = readWave(this, u32Num)
            
            import hex.HexUtils          
            % Generate a list of memory addresses
            
            cAddr = repmat(char(0), u32Num, 8);
            cFormat = repmat(char(0), u32Num, 1);
            
            for n = 1: u32Num
                % Each address stores a byte.  Read command returns four
                % bytes so incremenet address by 4 for each susbsequent
                % read comand
                
                offset = (n - 1) * 4;
                cAddr(n, :) = HexUtils.add(this.getBaseWaveAddr(1), dec2hex(offset));
                cFormat(n) = 'i'; 
            end
            
            % cAddr
            d = this.readSingle(cAddr, cFormat);
            
        end
        
        function d = readWave2(this, u32Num)
            d = this.readArray(this.getBaseWaveAddr(1), u32Num, 'i');
        end
        
        function d = readWave3(this, u32Num)
            d = this.readArrayLong(this.getBaseWaveAddr(1), u32Num, 'i');
        end
        %}
        
        
        % Wrapper around readArray() for reads that are so big that they
        % would fill the input buffer if put into a single readArray call
        
        function d = readArrayLong(this, cAddrHex32, u32Num, cType)
            
            import hex.HexUtils
            
            % Default return
            d = zeros(1, u32Num);
            
            
            % Based on the size of the input buffer, there is a maximum
            % number of reads readArray can do and not overfill the input
            % buffer. 
            
            switch (this.cConnection)
                case this.cCONNECTION_TCPCLIENT
                    dInputBuffer = 2^15;
                otherwise
                    dInputBuffer = this.s.InputBuffer;
            end
            
            % The response of a readArray command contians:
            %   one byte for start, 
            %   four bytes for start memory address,
            %   four bytes per read,
            %   one byte for stop
            % 
            % The max of reads can be caluclated:
                        
            dMaxReads = floor((dInputBuffer - 2 - 4)/4);
            
            % if u32Num > maxReads perform ceil(u32Num/maxReads)
            % readArray() calls, appending
            
            % Need to be careful here since we would be dividing an uint by
            % a double which keeps the type uint and would never get us the
            % fraction we want.  E.g., uint8(2)/1.1 = 2 {uint8} where as
            % 2/1.1 = 1.81 {double}
            
            dNum = double(u32Num);
            dNumReadArrays = ceil(dNum/dMaxReads);
            
            cMsg = sprintf(...
                'readArrayLong() max reads per readArray = %1.0f.  Requires %1.0f calls', ...
                dMaxReads, ...
                dNumReadArrays ...
            );
            this.msg(cMsg);
                        
            for n = 1 : dNumReadArrays
                
                if n < dNumReadArrays
                    dReads = dMaxReads;
                    % Array index
                    dStart = 1 + (n - 1) * dReads;
                    dEnd = n * dReads;
                else
                    dReads = u32Num - (n - 1) * dMaxReads;
                    % Array index
                    dStart = 1 + (n - 1)*dMaxReads;
                    dEnd = dStart + dReads - 1;
                    
                end
                
                % Offset the start memory address by 4 per read
                dAddrOffset = (n - 1) * 4 * dMaxReads;
                cAddr = HexUtils.add(cAddrHex32, dec2hex(dAddrOffset));
                
                % Issue readArray
                [dResult, lSuccess] = this.readArray(cAddr, dReads, cType);
                
                if ~lSuccess
                    % d is initialized to zeros so return that
                    return
                end
                
                d(dStart : dEnd) = dResult;
                
            end
                        
            
        end
        
        
        
        % Convert 32-bit hex string to desired representation based on its data type 
        % @param {char mx8} cHex - m-row x 8-col row-list of hex strings
        % @param {char 1x?} cType - data type (all input hex strings are 
        % assumed the same data type).  cType can be:
        %   'float' {double 1x1}, 
        %   'int32' {int32 1x1},
        %   'int20' cast as {int32 1x1},
        %   'uint32' {uint32 1x1}
        %   'hex' {char 1x8}
        
        function d = convertHex32(this, cHex, cType)
            
            import ieee.IeeeUtils
            
            switch cType
                case 'float' % The hex is a IEEE 32-bit hexadecimal format
                    d = IeeeUtils.hex32ToNumMulti(cHex);
                case 'int20'
                    % signed 20-bit int
                    d = hex2dec(cHex);
                    
                    % Values larger than 2^19 are negative.
                    idx = find(d > 2^19);
                    d(idx) = -(2^20 - d(idx));
                    
                case 'int32' 
                    % signed 32-bit int.  
                    % The hex is big endian. 
                    % hex2dec returns type {double}
                    
                    d = hex2dec(cHex);
                    
                    % Values larger than 2^31 are negative.
                    idx = find(d > 2^31);
                    d(idx) = -(2^32 - d(idx));
                   
                case 'uint32' 
                    % Unsigned int
                    % The hex is big endian.  Use hex2dec to con
                    d = hex2dec(cHex);
                case 'hex'
                    d = cHex;
                otherwise
                    fprintf(...
                        'valToHex32() UNSUPPORTED TYPE %s\n', ...
                        cType ...
                    );
            end 
            
        end
        
        
        function cValHex = castToHex32(this, xVal)
        
            import ieee.IeeeUtils
            
            switch class(xVal)
                case {'single', 'double'}
                    % Need to convert it to IEEE 32 hex representation
                    cValHex = IeeeUtils.numToHex32(xVal);
                case {'uint8', 'uint16', 'uint32'}
                    % Unsigned 8,16,32-bit int, convert to 8-char hex string
                    cValHex = dec2hex(xVal, 8);
                case 'int32'
                    % Signed 32-bit int.  If value is negative, offset
                    % by 2^32 to get it into [2^31 : 2^32] range.  Before
                    % doing this, need to cast as double so there is
                    % headroom for the shift by 2^32 (if the type really is
                    % {int32}, that type doesn't support values > 2^31 - 1,
                    % which is what we need to do
                    
                    dVal = double(xVal);
                    
                    idx = find(dVal < 0);
                    dVal(idx) = 2^32 + dVal(idx);
                    
                   
                    cValHex = dec2hex(dVal, 8);
                    
                case 'char'
                    % Already in hex representation
                    % Passed in hex, no conversion needed
                    cValHex = xVal;
                otherwise
                    fprintf(...
                        'valToHex32() UNSUPPORTED CLASS: %s\n', ...
                        class(xVal) ...
                    );
                    
            end
            
        end
        
       
        
        
        
        function msg(this, cMsg)
            % fprintf('%s\n', cMsg);
        end
        
        
        function write(this, dData)
            
            if isempty(this.s)
                this.init();
                this.connect();
            end
            
            switch this.cConnection
                case {this.cCONNECTION_RS232, this.cCONNECTION_TCPIP}
                     fwrite(this.s, dData);
                case this.cCONNECTION_TCPCLIENT
                     write(this.s, uint8(dData));
            end
        end
        
        function dResponse = read(this)
            switch this.cConnection
                case {this.cCONNECTION_TCPIP, this.cCONNECTION_RS232}
                    dResponse = fread(this.s, this.s.BytesAvailable);
                case this.cCONNECTION_TCPCLIENT
                    dResponse = read(this.s, this.s.BytesAvailable);
                    
%                     if ~isempty(error)
%                         fprintf('+npoint.LC400 read error');
%                         error
%                     end
                    
            end
                
        end
        
         
        
        function l = hasProp(this, c)
            
            l = false;
            if length(findprop(this, c)) > 0
                l = true;
            end
            
        end
        
    end
    
    
end

