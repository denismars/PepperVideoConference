package
{
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.ActivityEvent;
	import flash.events.Event;
	import flash.events.NetStatusEvent;
	import flash.events.StatusEvent;
	import flash.media.Camera;
	import flash.media.H264Level;
	import flash.media.H264Profile;
	import flash.media.H264VideoStreamSettings;
	import flash.media.Microphone;
	import flash.media.MicrophoneEnhancedMode;
	import flash.media.MicrophoneEnhancedOptions;
	import flash.media.SoundCodec;
	import flash.media.Video;
	import flash.net.GroupSpecifier;
	import flash.net.NetConnection;
	import flash.net.NetGroup;
	import flash.net.NetStream;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;
	import flash.utils.clearTimeout;
	import flash.utils.setInterval;
	import flash.utils.setTimeout;
	
	public class PepperVideoConference extends Sprite
	{
		private var video:Video;
		private var camera:Camera;
		private var mic:Microphone;
		private var netConnection:NetConnection;
		private var netGroup:NetGroup;
		private var groupSpec:GroupSpecifier;
		private var netStream:NetStream;
		private var myPeerId:String;
		private var peers:Object = new Object();
		private var videoWidth:int = 600;
		private var videoHeight:int = 440;
		private var server:String = "rtmfp://rndz2.meetings.io"; //"rtmfp://rndz2.meetings.io" //rtmfp:
		private var myText:TextField = new TextField();
		private var version:String = "27";
		
		public function PepperVideoConference()
		{
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.align = StageAlign.TOP_LEFT;
			stage.addEventListener(Event.RESIZE, resizeAll);
			myText.x = 20;
			myText.y = 500;
			myText.width = 300;
			myText.autoSize = TextFieldAutoSize.LEFT;
			myText.selectable = false;
			myText.text = "Initializing....";
			var format:TextFormat = new TextFormat();
			format.font = "Verdana";
			format.color = 0x333333;
			format.size = 10;
			myText.defaultTextFormat = format;
			addChild(myText);
			camera = Camera.getCamera();
			mic = Microphone.getEnhancedMicrophone();
			if(camera) loadCamera();
			else displayText("No Camera...");
			if(mic) loadMicrophone();
			else displayText("No Camera...");
		}
		
		private function displayText(text:String):void
		{
			myText.text = text;
		}
		
		private function loadCamera():void
		{
			displayText("Connecting Camera...");
			camera.addEventListener(ActivityEvent.ACTIVITY, activityHandler);
			camera.setMode(videoWidth, videoHeight, 15, true);
			//camera.setKeyFrameInterval(15);
			camera.setLoopback(false);
			camera.setQuality(0, 85);
			videoWidth = camera.width;
			videoHeight = camera.height;
			video = new Video(videoWidth, videoHeight);
			video.attachCamera(camera);
			peers['me'] = video;
			updateVideos();
			initNetConnection();
		}
		
		private function loadMicrophone():void
		{
			if(mic) {
				displayText("Connecting Mic...");
				mic.setUseEchoSuppression(true);
				mic.codec = SoundCodec.SPEEX;
				mic.framesPerPacket = 1;
				mic.encodeQuality = 6;
				mic.setSilenceLevel(-1);
				
				//microphone.noiseSuppressionLevel = 0; 
				mic.gain = 88;
				var options:MicrophoneEnhancedOptions = new MicrophoneEnhancedOptions();
				options.mode = MicrophoneEnhancedMode.FULL_DUPLEX;
				options.echoPath = 128;
				options.nonLinearProcessing = true;
				mic.enhancedOptions = options;
				mic.setUseEchoSuppression(true);
				mic.addEventListener(StatusEvent.STATUS, function(evt:StatusEvent):void{
					trace("Mic Status: "+evt.code);
				});
				
			}
		}
		
		private function initNetConnection():void
		{
			displayText("Connecting Net Connection...");
			netConnection = new NetConnection();
			netConnection.client = this;
			netConnection.addEventListener(NetStatusEvent.NET_STATUS, netConStatus);
			netConnection.connect(server);
		}
		
		private function netConStatus(evt:NetStatusEvent):void
		{
			trace("Net Connection Status: "+evt.info.code);
			if(evt.info.code === "NetConnection.Connect.Success") {
				myPeerId = netConnection.nearID;
				initNetGroup();
			}
			
			if(evt.info.code === "NetStream.Connect.Success") {
				publishCamera();
			}
		}
		
		private function initNetGroup():void
		{
			groupSpec = new GroupSpecifier("chromepeppersucks");
			groupSpec.multicastEnabled = true;
			groupSpec.postingEnabled = true;
			groupSpec.routingEnabled = true;
			groupSpec.serverChannelEnabled = true;

			netGroup = new NetGroup(netConnection, groupSpec.groupspecWithoutAuthorizations());
			netGroup.addEventListener(NetStatusEvent.NET_STATUS, netGroupStatus);
			
			netStream = new NetStream(netConnection, NetStream.DIRECT_CONNECTIONS);
			netStream.client = this;
			netStream.addEventListener(NetStatusEvent.NET_STATUS, netStreamStatus);
			netStream.bufferTime = -1;
			netStream.audioReliable = false;
			netStream.bufferTimeMax = -1;
			netStream.dataReliable = false;
			netStream.videoReliable = false;
			netStream.multicastAvailabilityUpdatePeriod = 0.02;
			netStream.multicastFetchPeriod = 0.02;
			netStream.multicastWindowDuration 0.006;
			
			var h264Settings:H264VideoStreamSettings = new H264VideoStreamSettings();
			h264Settings.setProfileLevel(H264Profile.BASELINE, H264Level.LEVEL_2_1);
			netStream.videoStreamSettings = h264Settings;
		}
		
		private function netGroupStatus(evt:NetStatusEvent):void
		{
			trace("Net Group Status: "+evt.info.code);
			if(evt.info.code === "NetGroup.Neighbor.Connect") {
				 displayText("New Peer Detected...");
				 peers[evt.info.peerID] = generatePeerVideo(evt.info.peerID);
				 updateVideos();
			}
			
			if(evt.info.code === "NetGroup.Neighbor.Disconnect") {
				removePeerVideo(evt.info.peerID);
			}
		}
		
		private function netStreamStatus(evt:NetStatusEvent):void
		{
			trace("Net Stream Status: "+evt.info.code);
		}
		
		private function publishCamera():void
		{
			if(camera) {
				netStream.attachCamera(camera);
			}
			
			if(mic) {
				netStream.attachAudio(mic);
			}
			displayText("Publishing Camera...");
			netStream.publish(myPeerId);
		}
		
		private var timer:uint;
		
		private function generatePeerVideo(peerId:String):Video
		{
			var peerVideo:Video = new Video(videoWidth, videoHeight);
			var peerNetStream:NetStream = new NetStream(netConnection, peerId);
			peerNetStream.client = this;
			peerNetStream.addEventListener(NetStatusEvent.NET_STATUS, peerNetStatus);
			
			peerNetStream.bufferTimeMax = -1;
			peerNetStream.bufferTime = -1;
			
			peerVideo.attachNetStream(peerNetStream);
			
			peerNetStream.play(peerId);
			
			function peerNetStatus(evt:NetStatusEvent):void
			{
				trace("Peer Net Stream Status: "+evt.info.code);
				if(evt.info.code === "NetStream.Play.PublishNotify" || evt.info.code === "NetStream.Play.Start") {
					clearTimeout(timer);
					timer = setInterval(function():void{
						var bps:Number = peerNetStream.info.currentBytesPerSecond;
						if(bps == 0) removePeerVideo(peerId);
						else trace("Bytes Per Second: "+bps);
						var latency:Number = peerNetStream.info.SRTT;
						if(latency > 0) {
							trace("Letency: "+latency);
							displayText("Ver: "+version+" - SRTT: "+latency+"ms - Buffer: "+int(bps)+" bytes/s");
						}
					}, 1000);
				}
			}
			
			return peerVideo;
		}
		
		private function activityHandler(event:ActivityEvent):void {
			//trace("activityHandler: " + event);
		}
		
		private function addParticipant():void
		{
			
		}
		
		private function removePeerVideo(peerId:String):void
		{
			if(peers[peerId]) {
				peers[peerId] = null;
				delete peers[peerId];
			}
			updateVideos();
		}
		
		private function updateVideos():void
		{
			this.removeChildren(1);
			var count:int = 0;
			for each(var video:Video in peers) {
				count++;
				this.addChild(video);
			}
			layOutInGrid(count);
		}
		
		private function resizeAll(evt:Event):void
		{
			
		}
		
		private function layOutInGrid(gap:Number=5):void
		{
			var nY:Number = 0;
			var nX:Number = 0;
			var maxH:Number = 0;
			var count:uint=1;
			var cols:uint = 2; //max 4 columns
			
			for (var i:uint = 0; i < this.numChildren; i++) {
				var tempVideo:* = this.getChildAt(i);
				if (tempVideo is Video) {
					tempVideo.x = nX;
					tempVideo.y = nY;
					
					//check if an object is bigger as the one before
					if (tempVideo.height > maxH) {
						maxH = tempVideo.height;
					}
					
					nX += (tempVideo.width+gap);
					//  reset row
					if (count%cols==0) {
						nY+=maxH+gap;
						nX=0;
					}
					count++;
				}
			}
		}
		
		public function onPlayStatus(info:Object):void {}
		public function onMetaData(info:Object):void {}
		public function onCuePoint(info:Object):void {}
		public function onTextData(info:Object):void {}
		public function close():void {}
	}
}