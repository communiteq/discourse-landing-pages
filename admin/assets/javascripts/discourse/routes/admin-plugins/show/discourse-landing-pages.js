import DiscourseRoute from "discourse/routes/discourse";
import LandingPage from "../../../models/landing-page";

export default class AdminPluginsShowDiscourseLandingPagesRoute extends DiscourseRoute {
  model() {
    return LandingPage.all();
  }
}
