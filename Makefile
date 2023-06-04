all: clean build fakesign ipa

build: 
				xcodebuild -project Transi.xcodeproj \
															-scheme Transi \
															-sdk iphoneos \
															archive -archivePath ./archive \
															CODE_SIGNING_REQUIRED=NO \
															AD_HOC_CODE_SIGNING_ALLOWED=YES \
															CODE_SIGNING_ALLOWED=NO \
															DEVELOPMENT_TEAM=XYZ0123456 \
															ORG_IDENTIFIER=eu.magicsk \
															DWARF_DSYM_FOLDER_PATH="."

fakesign:
					ldid -SReleaseEntitlements.plist archive.xcarchive/Products/Applications/Transi.app/Transi

ipa:
			mkdir Payload
			mkdir Payload/Transi.app
			cp -R archive.xcarchive/Products/Applications/Transi.app/ Payload/Transi.app/
			zip -r Transi.ipa Payload

clean: 
			rm -rf Payload
			rm -rf build
			rm -rf archive.xcarchive
			rm -rf Transi.app.dSYM
			rm -rf Transi.ipa
