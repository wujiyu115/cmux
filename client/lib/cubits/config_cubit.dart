import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';


enum ConfigSection {
  layout,
  session,
  sshProfiles,
  github,
  shortcuts,
  about,
  logs,
}

extension ConfigSectionRoute on ConfigSection {
  String get routeSegment => switch (this) {
    ConfigSection.sshProfiles => 'ssh-profiles',
    _ => name,
  };
}

class ConfigState extends Equatable {
  const ConfigState({
    this.section = ConfigSection.layout,
  });

  final ConfigSection section;

  String get title => switch (section) {
    ConfigSection.layout => 'Layout Configuration',
    ConfigSection.session => 'Session Configuration',
    ConfigSection.sshProfiles => 'SSH Servers',
    ConfigSection.github => 'GitHub',
    ConfigSection.shortcuts => 'Keyboard Shortcuts',
    ConfigSection.about => 'About',
    ConfigSection.logs => 'Logs',
  };

  String get breadcrumb => switch (section) {
    ConfigSection.layout => 'Config / Layout',
    ConfigSection.session => 'Config / Session',
    ConfigSection.sshProfiles => 'Config / SSH Servers',
    ConfigSection.github => 'Config / GitHub',
    ConfigSection.shortcuts => 'Config / Keyboard Shortcuts',
    ConfigSection.about => 'Config / About',
    ConfigSection.logs => 'Config / Logs',
  };

  ConfigState copyWith({ConfigSection? section}) {
    return ConfigState(
      section: section ?? this.section,
    );
  }

  @override
  List<Object?> get props => [section];
}

class ConfigCubit extends Cubit<ConfigState> {
  ConfigCubit() : super(const ConfigState());

  void selectSection(ConfigSection section) {
    if (state.section == section) return;
    emit(state.copyWith(section: section));
  }
}
